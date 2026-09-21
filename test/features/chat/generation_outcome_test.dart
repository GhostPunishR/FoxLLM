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
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm_native/foxllm_native.dart';

import '../../support/localized_app.dart';

void main() {
  group('l’issue d’une génération va jusqu’au fil', () {
    testWidgets('une réponse écourtée est annoncée et enregistrée', (
      tester,
    ) async {
      final backend = _OutcomeBackend();
      final store = _RecordingStore();
      await _pumpChat(tester, backend, store);

      await _send(tester, 'Ma question');
      backend.emit('Texte tronqué');
      await _settle(tester);
      // Le fournisseur annonce l'arrêt prématuré, puis ferme proprement.
      backend.incompleteReason = 'max_output_tokens';
      backend.finish();
      await _settle(tester);

      // Le défaut d'origine : le flux se terminait comme une réussite, et
      // rien à l'écran ne disait que la réponse était coupée.
      expect(find.textContaining('Réponse écourtée'), findsOneWidget);
      expect(find.textContaining('limite de longueur'), findsOneWidget);

      final saved = store.lastMessages.last;
      expect(saved.content, 'Texte tronqué');
      expect(saved.outcome, GenerationOutcome.incomplete);
      expect(saved.outcomeReason, 'max_output_tokens');
    });

    testWidgets('elle reste écourtée après une relecture de l’historique', (
      tester,
    ) async {
      final backend = _OutcomeBackend();
      final store = _RecordingStore();
      await _pumpChat(tester, backend, store);

      await _send(tester, 'Ma question');
      backend.emit('Texte tronqué');
      await _settle(tester);
      backend.incompleteReason = 'max_output_tokens';
      backend.finish();
      await _settle(tester);

      // Le fichier est relu tel qu'il a été écrit : passer par le JSON est ce
      // qui vérifie que le champ survit à l'aller-retour.
      final reread = ChatConversation.fromJson(
        store.saveCalls.last.single.toJson(),
      );
      expect(reread, isNotNull);
      expect(reread!.messages.last.outcome, GenerationOutcome.incomplete);
      expect(reread.messages.last.outcomeReason, 'max_output_tokens');
    });

    testWidgets('un arrêt demandé est noté comme tel', (tester) async {
      final backend = _OutcomeBackend();
      final store = _RecordingStore();
      await _pumpChat(tester, backend, store);

      await _send(tester, 'Ma question');
      backend.emit('Début');
      await _settle(tester);
      await tester.tap(find.byTooltip('Arrêter'));
      await _settle(tester);

      expect(find.textContaining('Réponse arrêtée'), findsOneWidget);
      expect(store.lastMessages.last.outcome, GenerationOutcome.cancelled);
    });

    testWidgets('un échec après des fragments est noté comme tel', (
      tester,
    ) async {
      final backend = _OutcomeBackend();
      final store = _RecordingStore();
      await _pumpChat(tester, backend, store);

      await _send(tester, 'Ma question');
      backend.emit('Début');
      await _settle(tester);
      backend.fail('le fournisseur a abandonné');
      await _settle(tester);

      expect(find.textContaining('Réponse interrompue'), findsOneWidget);
      expect(store.lastMessages.last.outcome, GenerationOutcome.failed);
    });

    testWidgets('une réponse allée au bout ne porte aucune mention', (
      tester,
    ) async {
      final backend = _OutcomeBackend();
      final store = _RecordingStore();
      await _pumpChat(tester, backend, store);

      await _send(tester, 'Ma question');
      backend.emit('Réponse entière');
      await _settle(tester);
      backend.finish();
      await _settle(tester);

      expect(find.textContaining('Réponse écourtée'), findsNothing);
      expect(store.lastMessages.last.outcome, GenerationOutcome.complete);
    });
  });

  group('une issue écourtée sans le moindre texte', () {
    testWidgets('est annoncée et enregistrée, au lieu de disparaître', (
      tester,
    ) async {
      final backend = _OutcomeBackend();
      final store = _RecordingStore();
      await _pumpChat(tester, backend, store);

      await _send(tester, 'Ma question');
      // Le fournisseur annonce l'arrêt avant d'avoir envoyé le moindre
      // fragment, puis referme proprement.
      backend.incompleteReason = 'content_filter';
      backend.finish();
      await _settle(tester);

      // Le défaut d'origine : l'issue n'était lue que s'il y avait du texte,
      // la bulle vide disparaissait et rien ne signalait la troncature.
      expect(find.textContaining('Aucun texte reçu'), findsOneWidget);
      expect(find.textContaining('filtré'), findsOneWidget);

      final saved = store.lastMessages.last;
      expect(saved.role, ChatRole.assistant);
      expect(saved.content, isEmpty);
      expect(saved.outcome, GenerationOutcome.incomplete);
      expect(saved.outcomeReason, 'content_filter');
    });

    testWidgets('reste annoncée après un rechargement de l’historique', (
      tester,
    ) async {
      final backend = _OutcomeBackend();
      final store = _RecordingStore();
      await _pumpChat(tester, backend, store);

      await _send(tester, 'Ma question');
      backend.incompleteReason = 'max_output_tokens';
      backend.finish();
      await _settle(tester);

      // Relu depuis le JSON réellement écrit, comme au lancement suivant.
      final reread = ChatConversation.fromJson(
        store.saveCalls.last.single.toJson(),
      );
      expect(reread, isNotNull);
      expect(reread!.messages.last.outcome, GenerationOutcome.incomplete);
      expect(reread.messages.last.outcomeReason, 'max_output_tokens');

      final reloaded = _OutcomeBackend();
      await _pumpChat(
        tester,
        reloaded,
        _RecordingStore(seed: <ChatConversation>[reread]),
      );
      await _settle(tester);
      expect(find.textContaining('Aucun texte reçu'), findsOneWidget);
    });

    testWidgets('laisse le message suivant en attente jusqu’à une reprise', (
      tester,
    ) async {
      final backend = _OutcomeBackend();
      final store = _RecordingStore();
      await _pumpChat(tester, backend, store);

      await _send(tester, 'Message A');
      await _type(tester, 'Message B');
      await tester.tap(find.byTooltip('Mettre en attente'));
      await tester.pump();

      backend.incompleteReason = 'max_output_tokens';
      backend.finish();
      await _settle(tester);

      expect(backend.generateCalls, <String>['Message A']);
      expect(find.text('1 message en attente'), findsOneWidget);

      await tester.tap(find.text('Réessayer'));
      await _settle(tester);
      backend.emit('Réponse B');
      backend.finish();
      await _settle(tester);

      expect(backend.generateCalls, <String>['Message A', 'Message B']);
    });

    testWidgets('ne détruit pas le fil qu’une régénération remplaçait', (
      tester,
    ) async {
      final backend = _OutcomeBackend();
      final store = _RecordingStore(
        seed: <ChatConversation>[
          ChatConversation(
            id: 1,
            title: 'Ma question',
            updatedAt: DateTime.now(),
            messages: <ChatMessage>[
              const ChatMessage.user('Ma question'),
              const ChatMessage.assistant('Première réponse'),
            ],
          ),
        ],
      );
      await _pumpChat(tester, backend, store);
      await _openThread(tester, 'Ma question');

      await tester.tap(find.byTooltip('Plus'));
      await _settle(tester);
      await tester.tap(find.text('Régénérer la réponse'));
      await _settle(tester);

      backend.incompleteReason = 'max_output_tokens';
      backend.finish();
      await _settle(tester);

      // La réponse remplacée n'est pas perdue : elle reste reprenable.
      expect(find.text('Version précédente conservée'), findsOneWidget);
      final saved = store.saveCalls.last.single;
      expect(saved.previousMessages?.map((m) => m.content), <String>[
        'Ma question',
        'Première réponse',
      ]);
    });
  });

  group('la file ne repart pas sur une réponse écourtée', () {
    testWidgets('elle attend une reprise explicite', (tester) async {
      final backend = _OutcomeBackend();
      final store = _RecordingStore();
      await _pumpChat(tester, backend, store);

      await _send(tester, 'Message A');
      backend.emit('Début');
      await tester.pump();

      await _type(tester, 'Message B');
      await tester.tap(find.byTooltip('Mettre en attente'));
      await tester.pump();

      backend.incompleteReason = 'max_output_tokens';
      backend.finish();
      await _settle(tester);

      // B reste en attente : enchaîner reviendrait à traiter une réponse
      // tronquée comme une réponse aboutie.
      expect(backend.generateCalls, <String>['Message A']);
      expect(find.text('1 message en attente'), findsOneWidget);

      await tester.tap(find.text('Réessayer'));
      await _settle(tester);
      backend.emit('Réponse B');
      backend.finish();
      await _settle(tester);

      expect(backend.generateCalls, <String>['Message A', 'Message B']);
    });

    testWidgets('la génération suivante ne porte plus l’état de la '
        'précédente', (tester) async {
      final backend = _OutcomeBackend();
      final store = _RecordingStore();
      await _pumpChat(tester, backend, store);

      await _send(tester, 'Message A');
      backend.emit('Tronqué');
      await _settle(tester);
      backend.incompleteReason = 'max_output_tokens';
      backend.finish();
      await _settle(tester);
      expect(find.textContaining('Réponse écourtée'), findsOneWidget);

      await _send(tester, 'Message B');
      backend.emit('Complet');
      await _settle(tester);
      backend.finish();
      await _settle(tester);

      // La mention reste sur la première réponse, pas sur la seconde.
      expect(find.textContaining('Réponse écourtée'), findsOneWidget);
      final messages = store.lastMessages;
      expect(messages.last.content, 'Complet');
      expect(messages.last.outcome, GenerationOutcome.complete);
    });
  });
}

// ---- utilitaires ----------------------------------------------------------

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump();
}

Future<void> _openThread(WidgetTester tester, String title) async {
  await tester.tap(find.byTooltip('Menu'));
  await _settle(tester);
  await tester.tap(find.text(title).last);
  await _settle(tester);
}

Future<void> _send(WidgetTester tester, String text) async {
  await _type(tester, text);
  await tester.tap(find.byTooltip('Envoyer'));
  await tester.pump();
}

/// Avance sans attendre l'immobilité : l'indicateur d'une génération en cours
/// tourne sans fin.
Future<void> _settle(WidgetTester tester, [int frames = 40]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pumpChat(
  WidgetTester tester,
  _OutcomeBackend backend,
  _RecordingStore store,
) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(backend.closeAll);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localLlmBackendProvider.overrideWithValue(backend),
        conversationStoreProvider.overrideWithValue(store),
      ],
      child: localizedApp(home: ChatScreen()),
    ),
  );
  await _settle(tester);
}

class _RecordingStore implements ConversationStore {
  _RecordingStore({this.seed = const <ChatConversation>[]});

  final List<ChatConversation> seed;
  final List<List<ChatConversation>> saveCalls = <List<ChatConversation>>[];

  List<ChatMessage> get lastMessages => saveCalls.last.first.messages;

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

/// Moteur distant simulé : ses réponses restent ouvertes, et il sait annoncer
/// qu'il les a écourtées.
class _OutcomeBackend implements LocalLlmBackend, IncompleteAwareBackend {
  final List<String> generateCalls = <String>[];
  final List<StreamController<String>> _streams = <StreamController<String>>[];

  @override
  String? incompleteReason;

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
  String? get loadedModelPath => '/models/test.gguf';

  @override
  Future<String> get nativeVersion async => 'test/0.0.0';

  @override
  Future<bool> get isModelLoaded async => true;

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
    generateCalls.add(messages.last.content);
    // Ce que fait le moteur réel : l'état de la réponse précédente ne doit
    // pas déborder sur celle qui commence.
    incompleteReason = null;
    final stream = StreamController<String>();
    _streams.add(stream);
    return stream.stream;
  }

  @override
  Future<void> stop() async => finish();

  @override
  Future<void> dispose() async {}
}
