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

/// Un remplacement qui tourne mal laisse deux versions du fil : celle qu'on
/// vient d'obtenir, souvent partielle, et celle qu'elle a remplacée. Les deux
/// doivent survivre au temps, à la navigation et au redémarrage.
void main() {
  group('la version remplacée reste reprenable', () {
    testWidgets('une erreur avant le premier fragment rend le fil intact, '
        'sans rien à reprendre', (tester) async {
      final backend = _Backend();
      final store = _RecordingStore(seed: _thread());
      await _pumpThread(tester, backend, store);

      await _regenerate(tester);
      backend.fail('le fournisseur a abandonné');
      await _settle(tester);

      expect(_inThread(tester, 'Première réponse'), isTrue);
      // Rien n'a été remplacé : il n'y a aucune version à proposer.
      expect(find.text('Version précédente conservée'), findsNothing);
    });

    testWidgets('une erreur après des fragments garde les deux versions', (
      tester,
    ) async {
      final backend = _Backend();
      final store = _RecordingStore(seed: _thread());
      await _pumpThread(tester, backend, store);

      await _regenerate(tester);
      backend.emit('Début de réponse');
      await _settle(tester);
      backend.fail('le fournisseur a abandonné');
      await _settle(tester);

      // Le résultat partiel est à l'écran, la version d'avant est conservée.
      expect(_inThread(tester, 'Début de réponse'), isTrue);
      expect(find.text('Version précédente conservée'), findsOneWidget);
      expect(_saved(store).previousMessages?.map((m) => m.content), <String>[
        'Ma question',
        'Première réponse',
      ]);
    });

    testWidgets('elle survit à l’attente, à la navigation et au rechargement', (
      tester,
    ) async {
      final backend = _Backend();
      final store = _RecordingStore(seed: _thread(withSecond: true));
      await _pumpThread(tester, backend, store);

      await _regenerate(tester);
      backend.emit('Début de réponse');
      await _settle(tester);
      backend.fail('le fournisseur a abandonné');
      await _settle(tester);
      expect(find.text('Version précédente conservée'), findsOneWidget);

      // Le défaut d'origine : la reprise tenait à l'action d'un bandeau de dix
      // secondes. Bien après, elle doit toujours être là.
      await tester.pump(const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 20));
      expect(find.text('Version précédente conservée'), findsOneWidget);

      // Aller voir ailleurs puis revenir ne l'efface pas.
      await _openThread(tester, 'Autre fil');
      expect(find.text('Version précédente conservée'), findsNothing);
      await _openThread(tester, 'Ma question');
      expect(find.text('Version précédente conservée'), findsOneWidget);

      // Et un relancement de l'application la retrouve : le fil est relu
      // depuis le JSON réellement écrit.
      final reread = store.saveCalls.last
          .map((c) => ChatConversation.fromJson(c.toJson()))
          .whereType<ChatConversation>()
          .toList();
      await _pumpChat(tester, _Backend(), _RecordingStore(seed: reread));
      await _openThread(tester, 'Ma question');

      expect(find.text('Version précédente conservée'), findsOneWidget);
      expect(_inThread(tester, 'Début de réponse'), isTrue);
    });

    testWidgets('rétablir rend l’ancienne version sans perdre la partielle', (
      tester,
    ) async {
      final backend = _Backend();
      final store = _RecordingStore(seed: _thread());
      await _pumpThread(tester, backend, store);

      await _regenerate(tester);
      backend.emit('Début de réponse');
      await _settle(tester);
      backend.fail('le fournisseur a abandonné');
      await _settle(tester);

      await tester.tap(find.text('Rétablir'));
      await _settle(tester);

      expect(_inThread(tester, 'Première réponse'), isTrue);
      expect(_inThread(tester, 'Début de réponse'), isFalse);
      // Le résultat partiel n'est pas jeté : il a pris la place de l'autre.
      expect(_saved(store).previousMessages?.map((m) => m.content), <String>[
        'Ma question',
        'Début de réponse',
      ]);

      // Le geste se refait dans l'autre sens.
      await tester.tap(find.text('Rétablir'));
      await _settle(tester);
      expect(_inThread(tester, 'Début de réponse'), isTrue);
      expect(_saved(store).previousMessages?.map((m) => m.content), <String>[
        'Ma question',
        'Première réponse',
      ]);
    });

    testWidgets('un remplacement réussi ne propose aucune restauration', (
      tester,
    ) async {
      final backend = _Backend();
      final store = _RecordingStore(seed: _thread());
      await _pumpThread(tester, backend, store);

      await _regenerate(tester);
      backend.emit('Seconde réponse');
      await _settle(tester);
      backend.finish();
      await _settle(tester);

      expect(_inThread(tester, 'Seconde réponse'), isTrue);
      expect(find.text('Version précédente conservée'), findsNothing);
      expect(_saved(store).previousMessages, isNull);
    });

    testWidgets('une modification bénéficie de la même protection', (
      tester,
    ) async {
      final backend = _Backend();
      final store = _RecordingStore(seed: _thread());
      await _pumpThread(tester, backend, store);

      await tester.longPress(_threadFinder('Ma question'));
      await _settle(tester);
      await tester.tap(find.text('Modifier le message'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).first, 'Question revue');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Envoyer'));
      await _settle(tester);

      backend.emit('Réponse partielle');
      await _settle(tester);
      backend.fail('le fournisseur a abandonné');
      await _settle(tester);

      expect(find.text('Version précédente conservée'), findsOneWidget);
      expect(_saved(store).previousMessages?.map((m) => m.content), <String>[
        'Ma question',
        'Première réponse',
      ]);
    });

    testWidgets('oublier la version conservée la retire pour de bon', (
      tester,
    ) async {
      final backend = _Backend();
      final store = _RecordingStore(seed: _thread());
      await _pumpThread(tester, backend, store);

      await _regenerate(tester);
      backend.emit('Début de réponse');
      await _settle(tester);
      backend.fail('le fournisseur a abandonné');
      await _settle(tester);

      await tester.tap(find.byTooltip('Oublier la version précédente'));
      await _settle(tester);

      expect(find.text('Version précédente conservée'), findsNothing);
      expect(_saved(store).previousMessages, isNull);
    });
  });
}

// ---- utilitaires ----------------------------------------------------------

List<ChatConversation> _thread({bool withSecond = false}) => <ChatConversation>[
  ChatConversation(
    id: 1,
    title: 'Ma question',
    updatedAt: DateTime(2026, 9, 14, 10),
    messages: <ChatMessage>[
      const ChatMessage.user('Ma question'),
      const ChatMessage.assistant('Première réponse'),
    ],
  ),
  if (withSecond)
    ChatConversation(
      id: 2,
      title: 'Autre fil',
      updatedAt: DateTime(2026, 9, 14, 9),
      messages: <ChatMessage>[
        const ChatMessage.user('Autre fil'),
        const ChatMessage.assistant('Autre réponse'),
      ],
    ),
];

ChatConversation _saved(_RecordingStore store) =>
    store.saveCalls.last.firstWhere((c) => c.id == 1);

Finder _threadFinder(String text) => find.descendant(
  of: find.byKey(const ValueKey<String>('chat-content')),
  matching: find.text(text),
);

bool _inThread(WidgetTester tester, String text) =>
    _threadFinder(text).evaluate().isNotEmpty;

Future<void> _regenerate(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Plus'));
  await _settle(tester);
  await tester.tap(find.text('Régénérer la réponse'));
  await _settle(tester);
}

Future<void> _openThread(WidgetTester tester, String title) async {
  await tester.tap(find.byTooltip('Menu'));
  await _settle(tester);
  await tester.tap(find.text(title).last);
  await _settle(tester);
}

/// Avance sans attendre l'immobilité : l'indicateur d'une génération en cours
/// tourne sans fin.
Future<void> _settle(WidgetTester tester, [int frames = 40]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pumpThread(
  WidgetTester tester,
  _Backend backend,
  _RecordingStore store,
) async {
  await _pumpChat(tester, backend, store);
  await _openThread(tester, 'Ma question');
}

Future<void> _pumpChat(
  WidgetTester tester,
  _Backend backend,
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
      child: const MaterialApp(home: ChatScreen()),
    ),
  );
  await _settle(tester);
}

class _RecordingStore implements ConversationStore {
  _RecordingStore({this.seed = const <ChatConversation>[]});

  final List<ChatConversation> seed;
  final List<List<ChatConversation>> saveCalls = <List<ChatConversation>>[];

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

/// Moteur de test : ses réponses restent ouvertes jusqu'à ce que le test en
/// décide.
class _Backend implements LocalLlmBackend {
  final List<StreamController<String>> _streams = <StreamController<String>>[];

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
    final stream = StreamController<String>();
    _streams.add(stream);
    return stream.stream;
  }

  @override
  Future<void> stop() async => finish();

  @override
  Future<void> dispose() async {}
}
