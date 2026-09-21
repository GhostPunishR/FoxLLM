// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/features/chat/chat_screen.dart';
import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/features/chat/conversations/conversation_store.dart';
import 'package:foxllm/features/settings/about/about_screen.dart';
import 'package:foxllm/features/settings/appearance_screen.dart';
import 'package:foxllm/features/settings/language_screen.dart';
import 'package:foxllm/features/settings/settings_screen.dart';
import 'package:foxllm/llm/backend/local_backend_provider.dart';
import 'package:foxllm/llm/backend/local_llm_backend.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/citation.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm/core/theme/fox_theme.dart';
import 'package:foxllm_native/foxllm_native.dart';

import '../support/localized_app.dart';

/// Contrôles d'accessibilité, sur les critères que Flutter sait vérifier.
///
/// Rien de subjectif ici : ce sont les règles d'Android et d'iOS sur la taille
/// des cibles tactiles, le contraste du texte, et la présence d'un libellé sur
/// ce qui se touche. Un bouton de 38 points de côté se rate, et un bouton sans
/// libellé n'existe pas pour qui navigue au lecteur d'écran.
void main() {
  group('écran de chat', () {
    testWidgets('cibles tactiles, contraste et libellés', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpChat(tester);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      handle.dispose();
    });

    testWidgets('un fil rempli garde ses cibles atteignables', (tester) async {
      // La barre d'actions d'une réponse porte les boutons les plus utilisés
      // de l'application : copier, relire, régénérer.
      final handle = tester.ensureSemantics();
      await _pumpChat(
        tester,
        conversations: <ChatConversation>[
          ChatConversation(
            id: 1,
            title: 'Un échange',
            updatedAt: DateTime(2026, 9, 19),
            messages: const <ChatMessage>[
              ChatMessage.user('Bonjour'),
              // Avec des sources : le bouton qui les ouvre n'apparaît que
              // dans ce cas, et se ratait donc aux contrôles.
              ChatMessage(
                role: ChatRole.assistant,
                content: 'Bonjour, comment puis-je aider ?',
                citations: <Citation>[
                  Citation(url: 'https://exemple.test', title: 'Exemple'),
                ],
              ),
            ],
          ),
        ],
      );
      // Le fil vit dans le menu latéral : il faut l'ouvrir pour l'atteindre.
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Un échange'));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      handle.dispose();
    });
  });

  group('écrans de réglages', () {
    testWidgets('Paramètres', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpScreen(tester, const SettingsScreen());

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      handle.dispose();
    });

    testWidgets('Apparence', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpScreen(tester, const AppearanceScreen());

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      handle.dispose();
    });

    testWidgets('Langue', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpScreen(tester, const LanguageScreen());

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      handle.dispose();
    });

    testWidgets('À propos', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpScreen(tester, const AboutScreen());

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      handle.dispose();
    });
  });
}

Future<void> _pumpChat(
  WidgetTester tester, {
  List<ChatConversation> conversations = const <ChatConversation>[],
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
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
  await tester.pumpAndSettle();
}

Future<void> _pumpScreen(WidgetTester tester, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [localLlmBackendProvider.overrideWithValue(_FakeBackend())],
      child: localizedApp(theme: FoxTheme.light.themeData, home: screen),
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
