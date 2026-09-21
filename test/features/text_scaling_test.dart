// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/theme/fox_theme.dart';
import 'package:foxllm/features/chat/chat_screen.dart';
import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/features/chat/conversations/conversation_store.dart';
import 'package:foxllm/features/settings/about/about_screen.dart';
import 'package:foxllm/features/settings/appearance_screen.dart';
import 'package:foxllm/features/settings/settings_screen.dart';
import 'package:foxllm/llm/backend/local_backend_provider.dart';
import 'package:foxllm/llm/backend/local_llm_backend.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm_native/foxllm_native.dart';

import '../support/localized_app.dart';

/// Android laisse agrandir le texte jusqu'à deux fois sa taille, et beaucoup
/// de gens s'en servent. Une mise en page qui déborde alors affiche la bande
/// rayée de Flutter par-dessus le contenu : l'écran devient inutilisable pour
/// ceux qui en ont le plus besoin.
///
/// Les tailles sont celles qu'Android propose vraiment dans ses réglages.
const _scales = <double>[1.3, 1.5, 2.0];

void main() {
  for (final scale in _scales) {
    testWidgets('le chat tient à ×$scale', (tester) async {
      await _pump(tester, const ChatScreen(), scale, seeded: true);
      expect(tester.takeException(), isNull);
    });

    testWidgets('les réglages tiennent à ×$scale', (tester) async {
      await _pump(tester, const SettingsScreen(), scale);
      expect(tester.takeException(), isNull);
    });

    testWidgets('l’apparence tient à ×$scale', (tester) async {
      await _pump(tester, const AppearanceScreen(), scale);
      expect(tester.takeException(), isNull);
    });

    testWidgets('À propos tient à ×$scale', (tester) async {
      await _pump(tester, const AboutScreen(), scale);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen,
  double scale, {
  bool seeded = false,
}) async {
  // Un écran de téléphone ordinaire, pas une tablette : c'est là que la place
  // manque.
  await tester.binding.setSurfaceSize(const Size(360, 780));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localLlmBackendProvider.overrideWithValue(_FakeBackend()),
        conversationStoreProvider.overrideWithValue(
          _SeededStore(
            seeded
                ? <ChatConversation>[
                    ChatConversation(
                      id: 1,
                      title: 'Un échange déjà ancien',
                      updatedAt: DateTime(2026, 9, 19),
                      messages: const <ChatMessage>[
                        ChatMessage.user('Bonjour'),
                        ChatMessage.assistant('Bonjour, comment aider ?'),
                      ],
                    ),
                  ]
                : const <ChatConversation>[],
          ),
        ),
      ],
      child: localizedApp(
        theme: FoxTheme.light.themeData,
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: scale,
          maxScaleFactor: scale,
          child: child!,
        ),
        home: screen,
      ),
    ),
  );
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
