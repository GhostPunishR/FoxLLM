// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/theme/fox_theme.dart';
import 'package:foxllm/features/chat/chat_screen.dart';
import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/features/chat/conversations/conversation_store.dart';
import 'package:foxllm/llm/backend/local_backend_provider.dart';
import 'package:foxllm/llm/backend/local_llm_backend.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm_native/foxllm_native.dart';

void main() {
  group('la vitesse traverse l’enregistrement', () {
    test('elle est relue telle qu’elle a été écrite', () {
      final saved = ChatConversation(
        id: 1,
        title: 'Un essai',
        updatedAt: DateTime(2026, 9, 20),
        messages: const <ChatMessage>[
          ChatMessage(
            role: ChatRole.assistant,
            content: 'Réponse locale',
            generationSpeed: 12.5,
          ),
        ],
      ).toJson();

      final reread = ChatConversation.fromJson(saved);
      expect(reread!.messages.single.generationSpeed, 12.5);
    });

    test('un historique écrit avant cette mesure se relit inchangé', () {
      // Le champ est absent des anciens enregistrements : son absence doit
      // rester une absence, et non devenir un zéro affiché.
      final legacy = <String, Object?>{
        'id': 2,
        'title': 'Ancien',
        'updatedAt': DateTime(2026, 9, 1).toIso8601String(),
        'messages': <Map<String, Object?>>[
          <String, Object?>{'role': 'assistant', 'content': 'Réponse'},
        ],
      };

      final reread = ChatConversation.fromJson(legacy);
      expect(reread!.messages.single.generationSpeed, isNull);
    });

    test('une valeur abîmée ne devient pas une vitesse', () {
      final broken = <String, Object?>{
        'id': 3,
        'title': 'Abîmé',
        'updatedAt': DateTime(2026, 9, 1).toIso8601String(),
        'messages': <Map<String, Object?>>[
          <String, Object?>{
            'role': 'assistant',
            'content': 'Réponse',
            'generationSpeed': 'très vite',
          },
        ],
      };

      expect(
        ChatConversation.fromJson(broken)!.messages.single.generationSpeed,
        isNull,
      );
    });
  });

  group('la vitesse s’affiche sous la réponse', () {
    testWidgets('une décimale en dessous de dix', (tester) async {
      await _pumpThread(tester, 8.42);
      expect(find.text('8,4 jetons/s'), findsOneWidget);
    });

    testWidgets('arrondie au-dessus de dix', (tester) async {
      // À trente jetons par seconde, le dixième ne veut plus rien dire.
      await _pumpThread(tester, 31.7);
      expect(find.text('32 jetons/s'), findsOneWidget);
    });

    testWidgets('rien pour une réponse distante', (tester) async {
      // Un fournisseur ne dit pas combien de jetons il a écrits par seconde :
      // inventer un chiffre serait pire que de n'en donner aucun.
      await _pumpThread(tester, null);
      expect(find.textContaining('jetons/s'), findsNothing);
    });
  });
}

Future<void> _pumpThread(WidgetTester tester, double? speed) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final store = _SeededStore(<ChatConversation>[
    ChatConversation(
      id: 1,
      title: 'Un échange',
      updatedAt: DateTime(2026, 9, 20),
      messages: <ChatMessage>[
        const ChatMessage.user('Bonjour'),
        ChatMessage(
          role: ChatRole.assistant,
          content: 'Bonjour, comment aider ?',
          generationSpeed: speed,
        ),
      ],
    ),
  ]);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localLlmBackendProvider.overrideWithValue(_FakeBackend()),
        conversationStoreProvider.overrideWithValue(store),
      ],
      child: MaterialApp(
        theme: FoxTheme.light.themeData,
        home: const ChatScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byTooltip('Menu'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Un échange'));
  await tester.pumpAndSettle();
}

class _SeededStore implements ConversationStore {
  _SeededStore(this.seeded);

  final List<ChatConversation> seeded;

  @override
  Future<List<ChatConversation>> load() async => seeded;

  @override
  Future<void> save(List<ChatConversation> conversations) async {}

  @override
  Future<void> clear() async {}
}

class _FakeBackend implements LocalLlmBackend {
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
  }) => Stream<String>.value('Réponse');

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
