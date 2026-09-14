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

void main() {
  group('envoi pendant la restauration du modèle', () {
    testWidgets('un nouveau chat annule l’envoi resté en attente', (
      tester,
    ) async {
      final backend = _GatedBackend();
      await _pumpChat(tester, backend: backend, restorableModel: true);

      await _type(tester, 'Question du premier fil');
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pump();

      // Le chargement du GGUF est en cours : rien n'est encore parti.
      expect(backend.generateCalls, isEmpty);

      await tester.tap(find.byTooltip('Nouveau chat'));
      await _pumpFrames(tester);
      await _type(tester, 'Brouillon du nouveau fil');

      backend.completeLoad();
      await tester.pumpAndSettle();

      expect(
        backend.generateCalls,
        isEmpty,
        reason: 'l’ancien texte ne part pas dans le nouveau fil',
      );
      expect(find.text('Question du premier fil'), findsNothing);
      expect(
        _draft(tester),
        'Brouillon du nouveau fil',
        reason: 'le brouillon de la nouvelle conversation est préservé',
      );
    });

    testWidgets('changer de conversation annule l’envoi resté en attente', (
      tester,
    ) async {
      final backend = _GatedBackend();
      await _pumpChat(
        tester,
        backend: backend,
        restorableModel: true,
        stored: <ChatConversation>[
          ChatConversation(
            id: 7,
            title: 'Fil précédent',
            updatedAt: DateTime(2026, 1, 1),
            messages: <ChatMessage>[const ChatMessage.user('Ancien message')],
          ),
        ],
      );

      await _type(tester, 'Question envoyée trop tôt');
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pump();

      await tester.tap(find.byTooltip('Menu'));
      await _pumpFrames(tester);
      await tester.tap(find.text('Fil précédent').last);
      await _pumpFrames(tester);

      backend.completeLoad();
      await tester.pumpAndSettle();

      expect(backend.generateCalls, isEmpty);
      expect(find.text('Question envoyée trop tôt'), findsNothing);
      expect(
        find.text('Ancien message'),
        findsWidgets,
        reason: 'la conversation ouverte est bien celle demandée',
      );
    });

    testWidgets('sans changement de fil, l’envoi aboutit normalement', (
      tester,
    ) async {
      final backend = _GatedBackend();
      await _pumpChat(tester, backend: backend, restorableModel: true);

      await _type(tester, 'Question posée');
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pump();

      backend.completeLoad();
      await tester.pumpAndSettle();

      expect(backend.generateCalls, hasLength(1));
      expect(backend.generateCalls.single.last.content, 'Question posée');
      expect(_draft(tester), isEmpty);
    });
  });

  group('écran détruit pendant une pièce jointe', () {
    testWidgets('la copie est effacée même si l’écran a disparu', (
      tester,
    ) async {
      final store = _GatedAttachmentStore();
      final picker = _GatedPicker()..completeWith(_picked('tardif.txt'));
      await _pumpChat(tester, attachmentStore: store, picker: picker);

      await _attach(tester);
      // La copie est en cours d'écriture quand l'écran est remplacé.
      expect(store.files, isEmpty);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      store.release();
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'lire ref après démontage levait une exception',
      );
      expect(
        store.files,
        isEmpty,
        reason: 'la copie devenue inutile ne reste pas sur l’appareil',
      );
      expect(store.deleted, hasLength(1));
    });

    testWidgets('un échec d’enregistrement après destruction reste muet', (
      tester,
    ) async {
      final store = _GatedAttachmentStore()..failSave = true;
      final picker = _GatedPicker()..completeWith(_picked('raté.txt'));
      await _pumpChat(tester, attachmentStore: store, picker: picker);

      await _attach(tester);
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      store.release();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('une sélection qui échoue après destruction reste muette', (
      tester,
    ) async {
      final picker = _GatedPicker();
      await _pumpChat(tester, picker: picker);

      await _attach(tester);
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      picker.failWith(const AttachmentException('sélecteur indisponible'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('cycle de vie', () {
    testWidgets('passer en arrière-plan écrit l’historique en attente', (
      tester,
    ) async {
      final store = _CountingStore();
      await _pumpChat(tester, conversationStore: store);

      await _type(tester, 'Message à conserver');
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pumpAndSettle();

      final beforeBackground = store.saves;

      // Android peut tuer le processus sans passer par `dispose()`.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(store.saves, greaterThan(beforeBackground));
      expect(store.last.single.messages.first.content, 'Message à conserver');
    });
  });

  group('pièces jointes et brouillon', () {
    testWidgets('un nouveau chat emporte les pièces jointes en attente', (
      tester,
    ) async {
      final store = _MemoryAttachmentStore();
      final backend = _RecordingBackend();
      await _pumpChat(
        tester,
        backend: backend,
        attachmentStore: store,
        picker: _GatedPicker()..completeWith(_picked('note.txt')),
      );

      await _attach(tester);
      expect(find.text('note.txt'), findsOneWidget);

      await tester.tap(find.byTooltip('Nouveau chat'));
      await tester.pumpAndSettle();

      expect(
        find.text('note.txt'),
        findsNothing,
        reason: 'la pièce jointe ne suit pas dans le nouveau fil',
      );
      expect(store.files, isEmpty, reason: 'la copie inutile est effacée');

      await _type(tester, 'Message sans pièce jointe');
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pumpAndSettle();

      expect(backend.calls.single.last.attachments, isEmpty);
    });

    testWidgets('changer de conversation emporte aussi les pièces jointes', (
      tester,
    ) async {
      final store = _MemoryAttachmentStore();
      await _pumpChat(
        tester,
        attachmentStore: store,
        picker: _GatedPicker()..completeWith(_picked('image.png')),
        stored: <ChatConversation>[
          ChatConversation(
            id: 3,
            title: 'Autre fil',
            updatedAt: DateTime(2026, 1, 1),
            messages: <ChatMessage>[const ChatMessage.user('Bonjour')],
          ),
        ],
      );

      await _attach(tester);
      expect(find.text('image.png'), findsOneWidget);

      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Autre fil').last);
      await tester.pumpAndSettle();

      expect(find.text('image.png'), findsNothing);
      expect(store.files, isEmpty);
    });

    testWidgets('une sélection terminée trop tard ne rejoint aucun fil', (
      tester,
    ) async {
      final store = _MemoryAttachmentStore();
      final picker = _GatedPicker();
      await _pumpChat(tester, attachmentStore: store, picker: picker);

      await _attach(tester);
      // Le sélecteur système est encore ouvert.
      expect(find.text('tardif.txt'), findsNothing);

      await tester.tap(find.byTooltip('Nouveau chat'));
      await tester.pumpAndSettle();

      picker.completeWith(_picked('tardif.txt'));
      await tester.pumpAndSettle();

      expect(
        find.text('tardif.txt'),
        findsNothing,
        reason: 'la pièce jointe visait le fil précédent',
      );
      expect(
        store.files,
        isEmpty,
        reason: 'sa copie ne reste pas sur l’appareil',
      );
    });

    testWidgets('une pièce jointe déjà envoyée n’est jamais effacée', (
      tester,
    ) async {
      final store = _MemoryAttachmentStore();
      final backend = _RecordingBackend();
      await _pumpChat(
        tester,
        backend: backend,
        attachmentStore: store,
        picker: _GatedPicker()..completeWith(_picked('rapport.txt')),
      );

      await _attach(tester);
      await _type(tester, 'Voici le rapport');
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pumpAndSettle();

      expect(store.files, hasLength(1));

      await tester.tap(find.byTooltip('Nouveau chat'));
      await tester.pumpAndSettle();

      expect(
        store.files,
        hasLength(1),
        reason: 'le fichier d’un message enregistré reste lisible',
      );
    });
  });
}

/// Avance le temps sans exiger la stabilité : pendant le chargement du GGUF,
/// la roue d'attente tourne indéfiniment.
Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 4; index++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

String _draft(WidgetTester tester) {
  return tester.widget<TextField>(find.byType(TextField)).controller!.text;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

Future<void> _attach(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Ajouter'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Joindre un fichier'));
  await tester.pumpAndSettle();
}

PickedAttachment _picked(String name) {
  return PickedAttachment(
    name: name,
    mimeType: 'text/plain',
    bytes: Uint8List.fromList(<int>[1, 2, 3]),
  );
}

Future<void> _pumpChat(
  WidgetTester tester, {
  LocalLlmBackend? backend,
  AttachmentStore? attachmentStore,
  AttachmentPicker? picker,
  ConversationStore? conversationStore,
  List<ChatConversation> stored = const <ChatConversation>[],
  bool restorableModel = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localLlmBackendProvider.overrideWithValue(
          backend ?? _RecordingBackend(),
        ),
        conversationStoreProvider.overrideWithValue(
          conversationStore ?? _MemoryStore(stored),
        ),
        attachmentStoreProvider.overrideWithValue(
          attachmentStore ?? _MemoryAttachmentStore(),
        ),
        attachmentPickerProvider.overrideWithValue(picker ?? _GatedPicker()),
        if (restorableModel)
          lastModelStoreProvider.overrideWithValue(
            _FakeLastModelStore('/models/memorise.gguf'),
          ),
      ],
      child: const MaterialApp(home: ChatScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Sélecteur dont le résultat n'arrive que sur commande.
class _GatedPicker implements AttachmentPicker {
  final Completer<PickedAttachment?> _gate = Completer<PickedAttachment?>();

  void completeWith(PickedAttachment? result) {
    if (!_gate.isCompleted) {
      _gate.complete(result);
    }
  }

  void failWith(Object error) {
    if (!_gate.isCompleted) {
      _gate.completeError(error);
    }
  }

  @override
  Future<PickedAttachment?> pick(AttachmentSource source) => _gate.future;
}

/// Magasin dont l'écriture n'aboutit que sur commande : c'est pendant cette
/// attente que l'écran peut disparaître.
class _GatedAttachmentStore extends AttachmentStore {
  final Map<String, Uint8List> files = <String, Uint8List>{};
  final List<ChatAttachment> deleted = <ChatAttachment>[];
  final Completer<void> _gate = Completer<void>();

  /// Fait échouer l'enregistrement au lieu de l'aboutir.
  bool failSave = false;

  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  @override
  Future<ChatAttachment> save({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    await _gate.future;
    if (failSave) {
      throw const AttachmentException('écriture impossible');
    }
    final path = '/mémoire/$name';
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
      deleted.add(attachment);
      files.remove(attachment.path);
    }
  }
}

/// Backend dont l'ouverture du GGUF n'aboutit que sur commande.
class _GatedBackend extends _RecordingBackend {
  final Completer<void> _gate = Completer<void>();
  String? _path;

  void completeLoad() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  @override
  String? get loadedModelPath => _path;

  @override
  Future<void> loadModel(String path) async {
    await _gate.future;
    _path = path;
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

/// Compte les écritures et retient la dernière, pour vérifier ce qui est
/// réellement conservé.
class _CountingStore implements ConversationStore {
  int saves = 0;
  List<ChatConversation> last = <ChatConversation>[];

  @override
  Future<List<ChatConversation>> load() async => <ChatConversation>[];

  @override
  Future<void> save(List<ChatConversation> conversations) async {
    saves++;
    last = conversations;
  }

  @override
  Future<void> clear() async {}
}

class _MemoryStore implements ConversationStore {
  _MemoryStore(this._initial);

  final List<ChatConversation> _initial;

  @override
  Future<List<ChatConversation>> load() async => _initial;

  @override
  Future<void> save(List<ChatConversation> conversations) async {}

  @override
  Future<void> clear() async {}
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

class _RecordingBackend implements LocalLlmBackend {
  final List<List<ChatMessage>> calls = <List<ChatMessage>>[];

  List<List<ChatMessage>> get generateCalls => calls;

  @override
  String get id => 'test';

  @override
  String get displayName => 'Backend de test';

  @override
  String? get loadedModelPath => '/models/test.gguf';

  @override
  Future<String> get nativeVersion async => 'test/0.0.0';

  @override
  Future<bool> get isModelLoaded async => loadedModelPath != null;

  @override
  Future<FoxLlmModelInfo?> get modelInfo async => null;

  @override
  Future<FoxLlmGenerationStats?> get lastGenerationStats async => null;

  @override
  Future<void> loadModel(String path) async {}

  @override
  Future<void> unloadModel() async {}

  @override
  Stream<String> generate({
    required List<ChatMessage> messages,
    GenerationSettings settings = const GenerationSettings(),
  }) {
    calls.add(List<ChatMessage>.of(messages));
    return Stream<String>.value('ok');
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
