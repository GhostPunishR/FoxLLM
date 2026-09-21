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

import '../../support/localized_app.dart';

/// Tailles dégénérées, que seul un appareil produit.
///
/// La première image d'un lancement arrive avant que la fenêtre ait ses
/// dimensions, donc avec une largeur et une hauteur nulles. Le mode immersif
/// allonge encore ce moment, le temps que les barres système cèdent la place.
///
/// Les bancs de test posent une taille d'écran fixe et ne voient jamais cet
/// instant : c'est exactement ce qui a permis à une largeur calculée par
/// soustraction de passer toute une campagne de tests avant de faire tomber
/// l'application au démarrage, sur le téléphone de quelqu'un.
/// Les tailles retenues sont celles qu'un appareil produit vraiment : la
/// fenêtre encore sans dimensions, le plus petit écran Android courant, et un
/// écran partagé en hauteur. Des largeurs plus absurdes provoquent bien des
/// débordements, mais aucun téléphone n'en a, et y plier la mise en page
/// coûterait plus qu'elle ne rapporte.
const _degenerate = <Size>[Size.zero, Size(320, 480), Size(360, 300)];

void main() {
  for (final size in _degenerate) {
    testWidgets('le chat se construit à ${size.width}×${size.height}', (
      tester,
    ) async {
      await _pump(tester, size, conversations: const <ChatConversation>[]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un fil se construit à ${size.width}×${size.height}', (
      tester,
    ) async {
      await _pump(
        tester,
        size,
        conversations: <ChatConversation>[
          ChatConversation(
            id: 1,
            title: 'Un échange',
            updatedAt: DateTime(2026, 9, 20),
            messages: const <ChatMessage>[
              ChatMessage.user('Bonjour'),
              ChatMessage.assistant('Bonjour, comment aider ?'),
            ],
          ),
        ],
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('la fenêtre grandit après la première image', (tester) async {
    // Le vrai enchaînement d'un lancement : rien, puis l'écran.
    await _pump(tester, Size.zero, conversations: const <ChatConversation>[]);
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(360, 780));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ChatScreen), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  required List<ChatConversation> conversations,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localLlmBackendProvider.overrideWithValue(_FakeBackend()),
        conversationStoreProvider.overrideWithValue(
          _SeededStore(conversations),
        ),
      ],
      child: localizedApp(
        theme: FoxTheme.light.themeData,
        home: const ChatScreen(),
      ),
    ),
  );
  await tester.pump();
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
  /// Le moteur local dit désormais pourquoi il s’est arrêté ; ce double
  /// n’a rien à écourter.
  @override
  String? get incompleteReason => null;

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
