// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/storage/api_key_store.dart';
import 'package:foxllm/core/theme/fox_theme.dart';
import 'package:foxllm/features/chat/chat_modes.dart';
import 'package:foxllm/features/chat/chat_screen.dart';
import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/features/chat/conversations/conversation_store.dart';
import 'package:foxllm/l10n/app_localizations.dart';
import 'package:foxllm/llm/backend/gemini_backend.dart';
import 'package:foxllm/llm/backend/local_backend_provider.dart';
import 'package:foxllm/llm/backend/local_llm_backend.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm/llm/personal_api/provider_config.dart';
import 'package:foxllm_native/foxllm_native.dart';

import '../../support/localized_app.dart';

void main() {
  group('ChatModesController', () {
    test('les deux modes partent inactifs', () {
      final container = _container(_MemoryStore());
      expect(container.read(chatModesProvider), const ChatModes());
    });

    test('relit les modes enregistrés', () async {
      final container = _container(
        _MemoryStore(const ChatModes(reasoning: true, webSearch: true)),
      );

      expect(container.read(chatModesProvider).reasoning, isFalse);
      final restored = await container
          .read(chatModesProvider.notifier)
          .resolved();
      expect(restored, const ChatModes(reasoning: true, webSearch: true));
    });

    test('bascule et enregistre chaque mode séparément', () async {
      final store = _MemoryStore();
      final container = _container(store);

      await container.read(chatModesProvider.notifier).toggleReasoning();
      expect(container.read(chatModesProvider).reasoning, isTrue);
      expect(container.read(chatModesProvider).webSearch, isFalse);
      expect(store.saved.reasoning, isTrue);

      await container.read(chatModesProvider.notifier).toggleReasoning();
      expect(container.read(chatModesProvider).reasoning, isFalse);
      expect(store.saved.reasoning, isFalse);

      await container.read(chatModesProvider.notifier).toggleWebSearch();
      expect(store.saved.webSearch, isTrue);
    });

    test('une bascule pendant la lecture n’est pas écrasée', () async {
      final container = _container(
        _MemoryStore(const ChatModes(reasoning: true), true),
      );

      container.read(chatModesProvider);
      await container.read(chatModesProvider.notifier).toggleWebSearch();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(container.read(chatModesProvider).webSearch, isTrue);
      expect(container.read(chatModesProvider).reasoning, isFalse);
    });

    test('un stockage illisible laisse les modes inactifs', () async {
      final container = _container(_BrokenStore());
      expect(
        await container.read(chatModesProvider.notifier).resolved(),
        const ChatModes(),
      );
    });
  });

  group('recherche web côté Gemini', () {
    test('l’outil de recherche n’est envoyé que si le mode est actif', () {
      final backend = GeminiBackend(
        model: 'gemini-2.0-flash',
        keyStore: _FakeKeyStore(),
        apiKeyPersistence: ApiKeyPersistence.session,
      );

      final without = jsonDecode(
        backend
            .buildRequest(
              apiKey: 'clé',
              messages: <ChatMessage>[const ChatMessage.user('Bonjour')],
              settings: const GenerationSettings(),
            )
            .body,
      );
      expect((without as Map)['tools'], isNull);

      final with_ = jsonDecode(
        backend
            .buildRequest(
              apiKey: 'clé',
              messages: <ChatMessage>[const ChatMessage.user('Actualité ?')],
              settings: const GenerationSettings(webSearch: true),
            )
            .body,
      );
      expect((with_ as Map)['tools'], <Object>[
        <String, Object>{'google_search': <String, Object>{}},
      ]);
    });
  });

  group('puces du composer', () {
    testWidgets('une puce inactive s’active et le dit', (tester) async {
      await _pumpChat(tester, _MemoryStore());

      expect(find.byTooltip('Réflexion : désactivé'), findsOneWidget);

      await tester.tap(find.text('Réflexion'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Réflexion : activé'), findsOneWidget);
      expect(find.textContaining('Réflexion activée'), findsOneWidget);
    });

    testWidgets('la recherche prévient que le moteur ne sait pas chercher', (
      tester,
    ) async {
      await _pumpChat(tester, _MemoryStore());

      await tester.tap(find.text('Rechercher'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Rechercher : activé'), findsOneWidget);
      expect(
        find.textContaining('ne sait pas consulter le web'),
        findsOneWidget,
      );
    });

    testWidgets('la réflexion ajoute sa consigne et de la marge', (
      tester,
    ) async {
      final backend = _RecordingBackend();
      await _pumpChat(tester, _MemoryStore(), backend: backend);

      await tester.tap(find.text('Réflexion'));
      await tester.pumpAndSettle();
      // Le message de confirmation flotte au-dessus du composer : sans cette
      // attente, l'appui suivant tomberait dessus.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Explique');
      await tester.pump();
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pumpAndSettle();

      final sent = backend.calls.single;
      expect(sent.first.role, ChatRole.system);
      expect(
        sent.first.content,
        lookupAppLocalizations(const Locale('fr')).reasoningInstruction,
      );
      expect(backend.settings.single.maxTokens, reasoningMaxTokens);
    });

    testWidgets('sans réflexion, aucune consigne ni marge ajoutée', (
      tester,
    ) async {
      final backend = _RecordingBackend();
      await _pumpChat(tester, _MemoryStore(), backend: backend);

      await tester.enterText(find.byType(TextField).first, 'Explique');
      await tester.pump();
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pumpAndSettle();

      expect(
        backend.calls.single.where((m) => m.role == ChatRole.system),
        isEmpty,
      );
      expect(
        backend.settings.single.maxTokens,
        const GenerationSettings().maxTokens,
      );
    });

    testWidgets(
      'la recherche active bloque un envoi que le moteur ignorerait',
      (tester) async {
        final backend = _RecordingBackend();
        await _pumpChat(
          tester,
          _MemoryStore(const ChatModes(webSearch: true)),
          backend: backend,
        );
        // Laisse la préférence enregistrée remonter jusqu'à l'écran.
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).first, 'Actualité ?');
        await tester.pump();
        await tester.tap(find.byTooltip('Envoyer'));
        await tester.pumpAndSettle();

        expect(backend.calls, isEmpty);
        expect(find.textContaining('recherche web demande'), findsOneWidget);
      },
    );
  });
}

ProviderContainer _container(ChatModesStore store) {
  final container = ProviderContainer(
    overrides: [chatModesStoreProvider.overrideWithValue(store)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpChat(
  WidgetTester tester,
  ChatModesStore store, {
  LocalLlmBackend? backend,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatModesStoreProvider.overrideWithValue(store),
        conversationStoreProvider.overrideWithValue(_EmptyStore()),
        localLlmBackendProvider.overrideWithValue(
          backend ?? _RecordingBackend(),
        ),
      ],
      child: localizedApp(
        theme: FoxTheme.light.themeData,
        home: const ChatScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _MemoryStore implements ChatModesStore {
  _MemoryStore([this.saved = const ChatModes(), this.delayed = false]);

  ChatModes saved;

  /// Simule un stockage lent, qui répond après le premier frame.
  final bool delayed;

  @override
  Future<ChatModes> load() async {
    if (delayed) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return saved;
  }

  @override
  Future<void> save(ChatModes modes) async => saved = modes;
}

class _BrokenStore implements ChatModesStore {
  @override
  Future<ChatModes> load() async => throw StateError('stockage indisponible');

  @override
  Future<void> save(ChatModes modes) async {}
}

class _EmptyStore implements ConversationStore {
  @override
  Future<List<ChatConversation>> load() async => <ChatConversation>[];

  @override
  Future<void> save(List<ChatConversation> conversations) async {}

  @override
  Future<void> clear() async {}
}

class _FakeKeyStore extends ApiKeyStore {
  @override
  Future<String?> read({
    required String providerId,
    required ApiKeyPersistence persistence,
  }) async => 'clé';
}

class _RecordingBackend implements LocalLlmBackend {
  final List<List<ChatMessage>> calls = <List<ChatMessage>>[];
  final List<GenerationSettings> settings = <GenerationSettings>[];

  @override
  String get id => 'fake';

  @override
  String get displayName => 'Backend de test';

  @override
  String? get loadedModelPath => '/models/test.gguf';

  @override
  Future<String> get nativeVersion async => 'fake/0.0.0';

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
    calls.add(List<ChatMessage>.of(messages));
    this.settings.add(settings);
    return Stream<String>.value('ok');
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
