// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  group('la régénération ne tronque rien avant d’être acceptée', () {
    testWidgets('sans modèle chargé, le fil reste entier', (tester) async {
      final backend = _Backend(loadedModelPath: null);
      final store = _RecordingStore();
      await _pumpThread(tester, backend, store);

      await _regenerate(tester);

      // Le défaut d'origine : la question et sa réponse partaient avant même
      // qu'on sache que l'envoi était impossible.
      expect(_inThread(tester, 'Ma question'), isTrue);
      expect(_inThread(tester, 'Première réponse'), isTrue);
      expect(find.textContaining('Charge un modèle'), findsOneWidget);
      expect(backend.generateCalls, isEmpty);

      // Et l'historique enregistré ne doit pas porter la troncature non plus.
      expect(store.lastMessages.map((m) => m.content), <String>[
        'Ma question',
        'Première réponse',
      ]);
    });

    testWidgets('une erreur avant le premier fragment rétablit l’ancienne '
        'réponse', (tester) async {
      final backend = _Backend(failGeneration: true);
      final store = _RecordingStore();
      await _pumpThread(tester, backend, store);

      await _regenerate(tester);
      await _settle(tester);

      // Le défaut d'origine : le fil était coupé avant l'appel au moteur, et
      // l'échec le laissait amputé de la réponse qu'il venait d'effacer.
      // Rien n'est arrivé du moteur, donc rien ne remplace rien.
      expect(_inThread(tester, 'Ma question'), isTrue);
      expect(_inThread(tester, 'Première réponse'), isTrue);
      expect(find.textContaining('Génération impossible'), findsOneWidget);

      // Et l'enregistrement dit la même chose que l'écran.
      expect(store.lastMessages.map((m) => m.content), <String>[
        'Ma question',
        'Première réponse',
      ]);
    });

    testWidgets('une erreur après des fragments garde le texte reçu et rend '
        'l’ancienne réponse à la demande', (tester) async {
      final backend = _Backend(hold: true);
      final store = _RecordingStore();
      await _pumpThread(tester, backend, store);

      await _regenerate(tester);
      backend.emit('Début de réponse');
      await _settle(tester);
      backend.fail('le fournisseur a abandonné');
      await _settle(tester);

      // Ce que l'utilisateur a vu arriver reste à l'écran : le jeter serait
      // une seconde perte.
      expect(_inThread(tester, 'Début de réponse'), isTrue);
      expect(store.lastMessages.map((m) => m.content), <String>[
        'Ma question',
        'Début de réponse',
      ]);

      // L'ancienne réponse n'est pas perdue pour autant : elle est à un geste,
      // et la perte n'est donc pas silencieuse.
      await tester.tap(find.text('Rétablir'));
      await _settle(tester);

      expect(_inThread(tester, 'Première réponse'), isTrue);
      expect(_inThread(tester, 'Début de réponse'), isFalse);
      expect(store.lastMessages.map((m) => m.content), <String>[
        'Ma question',
        'Première réponse',
      ]);
    });

    testWidgets('un remplacement réussi enregistre la nouvelle réponse', (
      tester,
    ) async {
      final backend = _Backend(hold: true);
      final store = _RecordingStore();
      await _pumpThread(tester, backend, store);

      await _regenerate(tester);
      backend.emit('Seconde réponse');
      await _settle(tester);
      backend.finish();
      await _settle(tester);

      expect(_inThread(tester, 'Seconde réponse'), isTrue);
      expect(_inThread(tester, 'Première réponse'), isFalse);
      expect(find.text('Rétablir'), findsNothing);
      expect(store.lastMessages.map((m) => m.content), <String>[
        'Ma question',
        'Seconde réponse',
      ]);
    });

    testWidgets('un échec revenu après un changement de fil ne touche pas '
        'celui qui est ouvert', (tester) async {
      final backend = _Backend(hold: true);
      final store = _RecordingStore();
      await _pumpTwoThreads(tester, backend, store);

      // Régénération lancée dans A, puis l'utilisateur ouvre B.
      await _regenerate(tester);
      await _settle(tester);
      await _openThread(tester, 'Question B');

      backend.fail('le fournisseur a abandonné');
      await _settle(tester);

      // Le fil ouvert est B : ni sa réponse ni son enregistrement ne doivent
      // recevoir quoi que ce soit de l'opération périmée.
      expect(_inThread(tester, 'Question B'), isTrue);
      expect(_inThread(tester, 'Réponse B'), isTrue);
      expect(_inThread(tester, 'Réponse A'), isFalse);
      expect(find.text('Rétablir'), findsNothing);

      final saved = store.saveCalls.last;
      expect(
        saved
            .firstWhere((c) => c.title == 'Question B')
            .messages
            .map((m) => m.content),
        <String>['Question B', 'Réponse B'],
      );
      // Et le fil A garde bien sa réponse : l'échec ne l'a pas laissé amputé.
      expect(
        saved
            .firstWhere((c) => c.title == 'Question A')
            .messages
            .map((m) => m.content),
        <String>['Question A', 'Réponse A'],
      );
    });

    testWidgets('la régénération préserve la pièce jointe de la question', (
      tester,
    ) async {
      final backend = _Backend(loadedModelPath: null);
      final store = _RecordingStore();
      await _pumpThread(tester, backend, store, withAttachment: true);

      await _regenerate(tester);

      expect(store.lastMessages.first.attachments, hasLength(1));
      expect(store.lastMessages.first.attachments.single.name, 'note.txt');
    });
  });

  group('une modification ne sort pas de sa conversation', () {
    testWidgets('valider après avoir ouvert un autre fil ne touche à rien', (
      tester,
    ) async {
      final backend = _Backend();
      final store = _RecordingStore();
      await _pumpTwoThreads(tester, backend, store);

      // Modification commencée dans le fil A.
      await tester.longPress(_threadFinder('Question A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modifier le message'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Texte de A');
      await tester.pump();

      // On ouvre B avant de valider.
      await _openThread(tester, 'Question B');

      // Le défaut d'origine : l'indice seul désignait le message de même rang
      // dans B, qui recevait le texte saisi pour A.
      expect(_inThread(tester, 'Question B'), isTrue);
      expect(_inThread(tester, 'Texte de A'), isFalse);
      expect(backend.generateCalls, isEmpty);
    });

    testWidgets('un nouveau chat abandonne la modification en cours', (
      tester,
    ) async {
      final backend = _Backend();
      final store = _RecordingStore();
      await _pumpThread(tester, backend, store);

      await tester.longPress(_threadFinder('Ma question'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modifier le message'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Nouveau chat'));
      await tester.pumpAndSettle();

      // Plus aucun champ de modification ouvert, et rien n'est parti.
      expect(find.text('Annuler'), findsNothing);
      expect(backend.generateCalls, isEmpty);
    });
  });

  group('la file n’emprunte pas le brouillon', () {
    testWidgets('démarrer un message en attente laisse le brouillon intact', (
      tester,
    ) async {
      final backend = _Backend(hold: true);
      final store = _RecordingStore();
      await _pumpEmpty(tester, backend, store);

      // A génère.
      await _type(tester, 'Message A');
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pump();
      backend.emit('Réponse A');
      await tester.pump();

      // B rejoint la file.
      await _type(tester, 'Message B');
      await tester.tap(find.byTooltip('Mettre en attente'));
      await tester.pump();

      // C reste dans le composeur.
      await _type(tester, 'Brouillon C');

      backend.finish();
      await _settle(tester);

      // Le défaut d'origine : le démarrage de B remplaçait les pièces jointes
      // du brouillon par les siennes. Le texte de C, lui, doit rester.
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Brouillon C',
      );
      expect(backend.generateCalls.last.last.content, 'Message B');

      backend.finish();
      await _settle(tester);
    });

    testWidgets('une réponse en échec n’enchaîne pas la file', (tester) async {
      final backend = _Backend(hold: true);
      final store = _RecordingStore();
      await _pumpEmpty(tester, backend, store);

      await _type(tester, 'Message A');
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pump();
      backend.emit('Réponse partielle');
      await tester.pump();

      await _type(tester, 'Message B');
      await tester.tap(find.byTooltip('Mettre en attente'));
      await tester.pump();

      // La réponse à A échoue en cours de route.
      backend.fail('le fournisseur a abandonné');
      await _settle(tester);

      // B ne part pas : enchaîner reviendrait à traiter l'échec comme une
      // réussite. Le texte déjà reçu, lui, reste affiché.
      expect(backend.generateCalls.map((call) => call.last.content), <String>[
        'Message A',
      ]);
      expect(find.textContaining('Génération impossible'), findsOneWidget);
      expect(_inThread(tester, 'Réponse partielle'), isTrue);
    });

    testWidgets('un message en attente refusé reste récupérable', (
      tester,
    ) async {
      final backend = _Backend(hold: true);
      final store = _RecordingStore();
      await _pumpEmpty(tester, backend, store);

      await _type(tester, 'Message A');
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pump();
      backend.emit('Réponse A');
      await tester.pump();

      await _type(tester, 'Message B');
      await tester.tap(find.byTooltip('Mettre en attente'));
      await tester.pump();

      // Le modèle disparaît avant que B ne parte.
      backend.loadedModelPath = null;
      backend.finish();
      await _settle(tester);

      // Aucune boucle de réessai ne s'est déclenchée.
      expect(backend.generateCalls.map((call) => call.last.content), <String>[
        'Message A',
      ]);
      expect(find.textContaining('Charge un modèle'), findsOneWidget);

      // B n'a pas été jeté pour autant : le modèle revenu, il repart au
      // premier envoi qui réussit. Le défaut d'origine le retirait de la file
      // avant de savoir si sa préparation aboutirait, et il était perdu.
      backend.loadedModelPath = '/models/test.gguf';
      // Le bandeau d'avertissement couvre le composeur : on le laisse partir
      // avant de viser le bouton.
      // Le bandeau d'avertissement se pose sur le composeur : on l'écarte
      // d'un balayage pour viser le bouton.
      await tester.drag(
        find.text('Charge un modèle GGUF avant de discuter.'),
        const Offset(0, 300),
      );
      await tester.pumpAndSettle();
      await _type(tester, 'Message C');
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pump();
      await _settle(tester);
      backend.finish();
      await _settle(tester);
      backend.finish();
      await _settle(tester);

      expect(backend.generateCalls.map((call) => call.last.content), <String>[
        'Message A',
        'Message C',
        'Message B',
      ]);
    });
  });
}

// ---- utilitaires ----------------------------------------------------------

Finder _threadFinder(String text) => find.descendant(
  of: find.byKey(const ValueKey<String>('chat-content')),
  matching: find.text(text),
);

bool _inThread(WidgetTester tester, String text) =>
    _threadFinder(text).evaluate().isNotEmpty;

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump();
}

Future<void> _regenerate(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Plus'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Régénérer la réponse'));
  // La génération lancée fait tourner l'indicateur de la bulle vide :
  // `pumpAndSettle` ne rendrait jamais la main.
  await _settle(tester);
}

Future<void> _openThread(WidgetTester tester, String title) async {
  // Pas de `pumpAndSettle` : le tiroir peut s'ouvrir pendant une génération,
  // dont l'indicateur tourne sans fin.
  await tester.tap(find.byTooltip('Menu'));
  await _settle(tester, 40);
  await tester.tap(find.text(title).last);
  await _settle(tester, 40);
}

/// Avance sans attendre l'immobilité : l'indicateur tourne pendant une
/// génération et `pumpAndSettle` ne rendrait jamais la main.
Future<void> _settle(WidgetTester tester, [int frames = 16]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

ChatConversation _thread(int id, String title, List<ChatMessage> messages) =>
    ChatConversation(
      id: id,
      title: title,
      updatedAt: DateTime.now().subtract(Duration(minutes: id)),
      messages: messages,
    );

Future<void> _pumpEmpty(
  WidgetTester tester,
  _Backend backend,
  _RecordingStore store,
) => _pump(tester, backend, store, <ChatConversation>[]);

Future<void> _pumpThread(
  WidgetTester tester,
  _Backend backend,
  _RecordingStore store, {
  bool withAttachment = false,
}) async {
  await _pump(tester, backend, store, <ChatConversation>[
    _thread(1, 'Ma question', <ChatMessage>[
      ChatMessage(
        role: ChatRole.user,
        content: 'Ma question',
        attachments: withAttachment
            ? <ChatAttachment>[
                const ChatAttachment(
                  name: 'note.txt',
                  path: '/tmp/note.txt',
                  mimeType: 'text/plain',
                  sizeBytes: 12,
                ),
              ]
            : const <ChatAttachment>[],
      ),
      const ChatMessage.assistant('Première réponse'),
    ]),
  ]);
  await _openThread(tester, 'Ma question');
}

Future<void> _pumpTwoThreads(
  WidgetTester tester,
  _Backend backend,
  _RecordingStore store,
) async {
  await _pump(tester, backend, store, <ChatConversation>[
    _thread(1, 'Question A', <ChatMessage>[
      const ChatMessage.user('Question A'),
      const ChatMessage.assistant('Réponse A'),
    ]),
    _thread(2, 'Question B', <ChatMessage>[
      const ChatMessage.user('Question B'),
      const ChatMessage.assistant('Réponse B'),
    ]),
  ]);
  await _openThread(tester, 'Question A');
}

Future<void> _pump(
  WidgetTester tester,
  _Backend backend,
  _RecordingStore store,
  List<ChatConversation> seed,
) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(backend.closeAll);
  store.seed = seed;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localLlmBackendProvider.overrideWithValue(backend),
        conversationStoreProvider.overrideWithValue(store),
      ],
      child: const MaterialApp(home: ChatScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

class _RecordingStore implements ConversationStore {
  List<ChatConversation> seed = <ChatConversation>[];
  final List<List<ChatConversation>> saveCalls = <List<ChatConversation>>[];

  /// Messages du fil enregistré en dernier, ou ceux du germe si rien n'a
  /// encore été écrit.
  List<ChatMessage> get lastMessages =>
      saveCalls.isEmpty ? seed.first.messages : saveCalls.last.first.messages;

  @override
  Future<List<ChatConversation>> load() async => seed;

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

/// Moteur de test : réponses tenues ouvertes, ou échec immédiat.
class _Backend implements LocalLlmBackend {
  _Backend({
    this.loadedModelPath = '/models/test.gguf',
    this.hold = false,
    this.failGeneration = false,
  });

  @override
  String? loadedModelPath;

  final bool hold;
  final bool failGeneration;

  final List<List<ChatMessage>> generateCalls = <List<ChatMessage>>[];
  final List<StreamController<String>> _streams = <StreamController<String>>[];

  void emit(String chunk) => _streams.last.add(chunk);

  void finish() {
    if (_streams.isNotEmpty && !_streams.last.isClosed) {
      unawaited(_streams.last.close());
    }
  }

  /// Termine la réponse en cours sur un échec, comme un fournisseur qui
  /// abandonne après avoir déjà envoyé du texte.
  void fail(String message) {
    if (_streams.isNotEmpty && !_streams.last.isClosed) {
      _streams.last.addError(StateError(message));
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
  Future<String> get nativeVersion async => 'test/0.0.0';

  @override
  Future<bool> get isModelLoaded async => loadedModelPath != null;

  @override
  Future<FoxLlmModelInfo?> get modelInfo async => null;

  @override
  Future<FoxLlmGenerationStats?> get lastGenerationStats async => null;

  @override
  Future<void> loadModel(String path) async => loadedModelPath = path;

  @override
  Future<void> unloadModel() async => loadedModelPath = null;

  @override
  Stream<String> generate({
    required List<ChatMessage> messages,
    GenerationSettings settings = const GenerationSettings(),
  }) {
    generateCalls.add(List<ChatMessage>.of(messages));
    if (failGeneration) {
      return Stream<String>.error(StateError('moteur indisponible'));
    }
    if (!hold) {
      return Stream<String>.value('Nouvelle réponse');
    }
    final stream = StreamController<String>();
    _streams.add(stream);
    return stream.stream;
  }

  @override
  Future<void> stop() async => finish();

  @override
  Future<void> dispose() async {}
}
