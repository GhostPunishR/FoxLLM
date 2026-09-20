// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/storage/last_model_store.dart';
import 'package:foxllm/features/chat/attachments/attachment_picker.dart';
import 'package:foxllm/features/chat/attachments/attachment_store.dart';
import 'package:foxllm/features/chat/chat_screen.dart';
import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/features/chat/conversations/conversation_store.dart';
import 'package:foxllm/llm/backend/local_backend_provider.dart';
import 'package:foxllm/llm/backend/local_llm_backend.dart';
import 'package:foxllm/llm/model/chat_attachment.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm_native/foxllm_native.dart';

import '../../support/localized_app.dart';

void main() {
  group('identité du fil qui vient de naître', () {
    testWidgets('un message mis en attente avant la création du fil y '
        'arrive quand même', (tester) async {
      final backend = _QueueBackend();
      final store = _GateStore();
      await _pumpChat(tester, backend: backend, conversationStore: store);

      // Le premier message d'un nouveau chat attend la relecture de
      // l'historique : pendant ce temps, le fil n'a pas encore d'identifiant.
      await _type(tester, 'Message A');
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pump();

      await _type(tester, 'Message B');
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pump();
      expect(find.text('1 message en attente'), findsOneWidget);

      store.release();
      await _settle(tester);
      backend.emit('Réponse A');
      backend.finish();
      await _settle(tester);
      backend.emit('Réponse B');
      backend.finish();
      await _settle(tester);

      // Le défaut d'origine : B était préparé avec `null`, A créait le fil, et
      // B se faisait refuser pour un identifiant qu'il ne pouvait pas porter.
      expect(backend.generateCalls.map((call) => call.last.content), <String>[
        'Message A',
        'Message B',
      ]);
      expect(find.text('1 message en attente'), findsNothing);

      // Les deux sont dans le même fil, dans l'ordre.
      final saved = store.saveCalls.last;
      expect(saved, hasLength(1));
      expect(saved.single.messages.map((m) => m.content), <String>[
        'Message A',
        'Réponse A',
        'Message B',
        'Réponse B',
      ]);
    });

    testWidgets('quitter le fil pendant la préparation d’un message en '
        'attente ne le fait pas revenir', (tester) async {
      final backend = _QueueBackend();
      await _pumpChat(
        tester,
        backend: backend,
        restorableModel: true,
        stored: <ChatConversation>[
          _thread(1, 'Question A', 'Réponse A'),
          _thread(2, 'Question B', 'Réponse B'),
        ],
      );
      await _openThread(tester, 'Question A');

      await _type(tester, 'Message 1');
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pump();

      await _type(tester, 'Message 2');
      await tester.tap(find.byTooltip('Mettre en attente'));
      await tester.pump();

      // Le modèle se referme : la préparation du message en attente va devoir
      // le rouvrir, et cette ouverture n'aboutit que sur commande.
      backend.closeModel();
      backend.emit('Fin');
      backend.finish();
      await _settle(tester);

      // Pendant cette préparation, l'utilisateur ouvre un autre fil.
      await _openThread(tester, 'Question B');
      backend.completeLoad();
      await _settle(tester);

      // Le message refusé appartenait au fil quitté : il ne revient pas dans
      // la file, et ne part surtout pas dans le fil ouvert maintenant.
      expect(find.text('1 message en attente'), findsNothing);
      expect(backend.generateCalls.map((call) => call.last.content), <String>[
        'Message 1',
      ]);
    });
  });

  group('récupération d’un message refusé', () {
    testWidgets('« Réessayer » le renvoie sans message sans rapport', (
      tester,
    ) async {
      final backend = _QueueBackend();
      await _pumpChat(tester, backend: backend);
      await _refuseQueued(tester, backend);

      expect(find.text('1 message en attente'), findsOneWidget);

      backend.reopenModel();
      await _dismissSnack(tester);
      await tester.tap(find.text('Réessayer'));
      await _settle(tester);
      backend.emit('Réponse B');
      backend.finish();
      await _settle(tester);

      expect(backend.generateCalls.map((call) => call.last.content), <String>[
        'Message A',
        'Message B',
      ]);
      expect(find.text('1 message en attente'), findsNothing);
    });

    testWidgets('« Retirer » l’enlève pour de bon', (tester) async {
      final backend = _QueueBackend();
      await _pumpChat(tester, backend: backend);
      await _refuseQueued(tester, backend);

      await _dismissSnack(tester);
      await tester.tap(find.byTooltip('Retirer de la file'));
      await _settle(tester);

      expect(find.text('1 message en attente'), findsNothing);

      // Rien ne le ressuscite : un envoi qui réussit ne le ramène pas.
      backend.reopenModel();
      await _type(tester, 'Message C');
      await tester.tap(find.byTooltip('Envoyer'));
      await _settle(tester);
      backend.emit('Réponse C');
      backend.finish();
      await _settle(tester);

      expect(backend.generateCalls.map((call) => call.last.content), <String>[
        'Message A',
        'Message C',
      ]);
    });

    testWidgets('reprendre un message en attente ne perd ni brouillon ni '
        'pièce jointe', (tester) async {
      final backend = _QueueBackend();
      final picker = _ScriptedPicker(<String>['jointe-b.txt', 'jointe-c.txt']);
      final store = _GateStore()..release();
      await _pumpChat(
        tester,
        backend: backend,
        picker: picker,
        conversationStore: store,
      );

      await _type(tester, 'Message A');
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pump();
      backend.emit('Réponse A');
      await tester.pump();

      // B part en file avec sa pièce jointe.
      await _attach(tester);
      await _type(tester, 'Message B');
      await tester.tap(find.byTooltip('Mettre en attente'));
      await _settle(tester);

      // Un autre brouillon s'écrit pendant l'attente, avec le sien.
      await _attach(tester);
      await _type(tester, 'Brouillon C');

      // L'utilisateur reprend B pour le corriger.
      await tester.tap(find.text('Message B'));
      await _settle(tester);

      expect(_draft(tester), 'Message B');
      expect(find.text('jointe-b.txt'), findsOneWidget);
      // Le brouillon n'est pas jeté : il prend la place de B dans la file,
      // avec sa propre pièce jointe.
      expect(find.text('Brouillon C'), findsOneWidget);
      expect(find.text('1 message en attente'), findsOneWidget);

      backend.finish();
      await _settle(tester);
      backend.emit('Réponse C');
      backend.finish();
      await _settle(tester);

      // Le message parti est bien celui du brouillon, avec sa pièce jointe :
      // c'est le fil enregistré qui en garde la référence, la requête envoyée
      // au moteur portant, elle, le contenu du fichier.
      final saved = store.saveCalls.last.single.messages;
      final sent = saved.lastWhere((m) => m.role == ChatRole.user);
      expect(sent.content, 'Brouillon C');
      expect(sent.attachments.single.name, 'jointe-c.txt');
    });
  });
}

// ---- utilitaires ----------------------------------------------------------

/// Met un message en file, puis fait refuser sa préparation.
Future<void> _refuseQueued(WidgetTester tester, _QueueBackend backend) async {
  await _type(tester, 'Message A');
  await tester.tap(find.byTooltip('Envoyer'));
  await tester.pump();

  await _type(tester, 'Message B');
  await tester.tap(find.byTooltip('Mettre en attente'));
  await tester.pump();

  // Plus de modèle et rien à rouvrir : la préparation de B est refusée.
  backend.closeModel();
  backend.emit('Réponse A');
  backend.finish();
  await _settle(tester);
}

Future<void> _dismissSnack(WidgetTester tester) async {
  final snack = find.textContaining('Charge un modèle');
  if (snack.evaluate().isEmpty) {
    return;
  }
  await tester.drag(snack.first, const Offset(0, 300));
  await _settle(tester);
}

ChatConversation _thread(int id, String title, String answer) =>
    ChatConversation(
      id: id,
      title: title,
      updatedAt: DateTime.now().subtract(Duration(minutes: id)),
      messages: <ChatMessage>[
        ChatMessage.user(title),
        ChatMessage.assistant(answer),
      ],
    );

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump();
}

String _draft(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).first).controller!.text;

Future<void> _attach(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Ajouter'));
  await _settle(tester);
  await tester.tap(find.text('Joindre un fichier'));
  await _settle(tester);
}

Future<void> _openThread(WidgetTester tester, String title) async {
  await tester.tap(find.byTooltip('Menu'));
  await _settle(tester);
  await tester.tap(find.text(title).last);
  await _settle(tester);
}

/// Avance sans attendre l'immobilité : l'indicateur d'une génération en cours
/// tourne sans fin, et `pumpAndSettle` ne rendrait jamais la main.
Future<void> _settle(WidgetTester tester, [int frames = 40]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pumpChat(
  WidgetTester tester, {
  required _QueueBackend backend,
  ConversationStore? conversationStore,
  AttachmentPicker? picker,
  List<ChatConversation> stored = const <ChatConversation>[],
  bool restorableModel = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(backend.closeAll);

  final store = conversationStore ?? (_GateStore(stored)..release());

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localLlmBackendProvider.overrideWithValue(backend),
        conversationStoreProvider.overrideWithValue(store),
        attachmentStoreProvider.overrideWithValue(_MemoryAttachmentStore()),
        if (picker != null) attachmentPickerProvider.overrideWithValue(picker),
        if (restorableModel)
          lastModelStoreProvider.overrideWithValue(
            _FakeLastModelStore('/models/memorise.gguf'),
          ),
      ],
      child: localizedApp(home: ChatScreen()),
    ),
  );
  await _settle(tester);
}

/// Magasin dont la relecture n'aboutit que sur commande.
class _GateStore implements ConversationStore {
  _GateStore([this.seed = const <ChatConversation>[]]);

  final List<ChatConversation> seed;
  final Completer<void> _gate = Completer<void>();
  final List<List<ChatConversation>> saveCalls = <List<ChatConversation>>[];

  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  @override
  Future<List<ChatConversation>> load() async {
    await _gate.future;
    return seed;
  }

  @override
  Future<void> save(List<ChatConversation> conversations) async {
    saveCalls.add(
      conversations
          .map(
            (c) => ChatConversation(
              id: c.id,
              title: c.title,
              updatedAt: c.updatedAt,
              messages: List<ChatMessage>.of(c.messages),
              previousMessages: c.previousMessages == null
                  ? null
                  : List<ChatMessage>.of(c.previousMessages!),
            ),
          )
          .toList(),
    );
  }

  @override
  Future<void> clear() async {}
}

/// Moteur dont les réponses restent ouvertes et dont l'ouverture du modèle
/// n'aboutit que sur commande.
class _QueueBackend implements LocalLlmBackend {
  String? _path = '/models/test.gguf';
  Completer<void>? _loadGate;

  final List<List<ChatMessage>> generateCalls = <List<ChatMessage>>[];
  final List<StreamController<String>> _streams = <StreamController<String>>[];

  /// Referme le modèle : la préparation suivante devra le rouvrir, et cette
  /// ouverture attendra [completeLoad].
  void closeModel() {
    _path = null;
    _loadGate = Completer<void>();
  }

  /// Rouvre le modèle sans passer par un chargement.
  void reopenModel() {
    _path = '/models/test.gguf';
    _loadGate = null;
  }

  void completeLoad() {
    final gate = _loadGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  void emit(String chunk) {
    if (_streams.isNotEmpty && !_streams.last.isClosed) {
      _streams.last.add(chunk);
    }
  }

  void finish() {
    if (_streams.isNotEmpty && !_streams.last.isClosed) {
      unawaited(_streams.last.close());
    }
  }

  void closeAll() {
    for (final stream in _streams) {
      if (!stream.isClosed) {
        unawaited(stream.close());
      }
    }
  }

  @override
  String get id => 'test';

  @override
  String get displayName => 'Backend de test';

  @override
  String? get loadedModelPath => _path;

  @override
  Future<String> get nativeVersion async => 'test/0.0.0';

  @override
  Future<bool> get isModelLoaded async => _path != null;

  @override
  Future<FoxLlmModelInfo?> get modelInfo async => null;

  @override
  Future<FoxLlmGenerationStats?> get lastGenerationStats async => null;

  @override
  Future<void> loadModel(String path) async {
    final gate = _loadGate;
    if (gate != null) {
      await gate.future;
    }
    _path = path;
  }

  @override
  Future<void> unloadModel() async => _path = null;

  @override
  Stream<String> generate({
    required List<ChatMessage> messages,
    GenerationSettings settings = const GenerationSettings(),
  }) {
    generateCalls.add(List<ChatMessage>.of(messages));
    final stream = StreamController<String>();
    _streams.add(stream);
    return stream.stream;
  }

  @override
  Future<void> stop() async => finish();

  @override
  Future<void> dispose() async {}
}

/// Sélecteur qui rend, dans l'ordre, les pièces jointes prévues.
class _ScriptedPicker implements AttachmentPicker {
  _ScriptedPicker(this._names);

  final List<String> _names;
  int _index = 0;

  @override
  Future<PickedAttachment?> pick(AttachmentSource source) async {
    if (_index >= _names.length) {
      return null;
    }
    return PickedAttachment(
      name: _names[_index++],
      mimeType: 'text/plain',
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
    );
  }
}

class _MemoryAttachmentStore extends AttachmentStore {
  final Map<String, Uint8List> files = <String, Uint8List>{};

  @override
  Future<ChatAttachment> save({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final path = '/mémoire/${files.length}_$name';
    files[path] = bytes;
    return ChatAttachment(
      name: name,
      path: path,
      mimeType: mimeType,
      sizeBytes: bytes.length,
    );
  }

  @override
  Future<Uint8List?> read(ChatAttachment attachment) async =>
      files[attachment.path];

  @override
  Future<void> delete(Iterable<ChatAttachment> attachments) async {
    for (final attachment in attachments) {
      files.remove(attachment.path);
    }
  }
}

class _FakeLastModelStore implements LastModelStore {
  _FakeLastModelStore(this.path);

  final String? path;

  @override
  Future<String?> load() async => path;

  @override
  Future<void> save(String path) async {}

  @override
  Future<void> clear() async {}
}
