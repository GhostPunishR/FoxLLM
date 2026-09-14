// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

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

void main() {
  testWidgets('le titre suit le fil ouvert', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localLlmBackendProvider.overrideWithValue(_ShortAnswerBackend()),
          conversationStoreProvider.overrideWithValue(_EmptyStore()),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Tant qu'aucun fil n'existe, il n'y a pas de titre à donner.
    expect(_topBarTitle(tester), 'FoxLLM');

    await tester.enterText(
      find.byType(TextField),
      'Comment planter un cerisier',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Envoyer'));
    await tester.pumpAndSettle();

    expect(_topBarTitle(tester), 'Comment planter un cerisier');

    // Un nouveau fil repart sans titre.
    await tester.tap(find.byTooltip('Nouveau chat'));
    await tester.pumpAndSettle();

    expect(_topBarTitle(tester), 'FoxLLM');
  });

  testWidgets('un titre trop long est coupé, pas replié', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localLlmBackendProvider.overrideWithValue(_ShortAnswerBackend()),
          conversationStoreProvider.overrideWithValue(_EmptyStore()),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'Explique-moi pourquoi le ciel est bleu et la mer aussi, en détail',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Envoyer'));
    await tester.pumpAndSettle();

    final title = _topBarText(tester);
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    // Le titre tient entre les deux boutons, sans passer dessous.
    final titleRect = tester.getRect(find.text(title.data!));
    expect(
      titleRect.left,
      greaterThan(tester.getRect(find.byTooltip('Menu')).right),
    );
    expect(
      titleRect.right,
      lessThan(tester.getRect(find.byTooltip('Nouveau chat')).left),
    );

    // La barre du haut garde sa hauteur : le titre ne la fait pas grandir.
    final menu = tester.getRect(find.byTooltip('Menu'));
    final newChat = tester.getRect(find.byTooltip('Nouveau chat'));
    expect(menu.top, newChat.top);
    expect(tester.takeException(), isNull);
  });

  testWidgets('le fil de messages ne passe jamais sous les boutons du haut', (
    tester,
  ) async {
    // Encoche comprise : les boutons doivent aussi rester sous la barre d'état.
    tester.view.padding = const FakeViewPadding(top: 96);
    addTearDown(tester.view.reset);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localLlmBackendProvider.overrideWithValue(_LongAnswerBackend()),
          conversationStoreProvider.overrideWithValue(_EmptyStore()),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Écris-moi du code');
    await tester.pump();
    await tester.tap(find.byTooltip('Envoyer'));
    await tester.pumpAndSettle();

    final content = tester.getRect(
      find.byKey(const ValueKey<String>('chat-content')),
    );
    final menu = tester.getRect(find.byTooltip('Menu'));
    final newChat = tester.getRect(find.byTooltip('Nouveau chat'));

    expect(content.overlaps(menu), isFalse);
    expect(content.overlaps(newChat), isFalse);
    expect(content.top, greaterThanOrEqualTo(menu.bottom));
    // La barre laisse la zone d'état libre (padding donné en pixels physiques).
    final topInset = 96 / tester.view.devicePixelRatio;
    expect(menu.top, greaterThanOrEqualTo(topInset));

    // Après défilement, le contenu reste découpé au même endroit.
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();

    final scrolled = tester.getRect(
      find.byKey(const ValueKey<String>('chat-content')),
    );
    expect(scrolled.top, content.top);
    expect(scrolled.overlaps(menu), isFalse);
    expect(tester.takeException(), isNull);
  });
}

/// Le texte de la barre du haut : le seul qui soit à hauteur des deux boutons.
Text _topBarText(WidgetTester tester) {
  final menu = tester.getRect(find.byTooltip('Menu'));
  for (final element in find.byType(Text).evaluate()) {
    final box = element.renderObject;
    if (box is! RenderBox || !box.hasSize) {
      continue;
    }
    final center = box.localToGlobal(box.size.center(Offset.zero));
    if (center.dy >= menu.top && center.dy <= menu.bottom) {
      return element.widget as Text;
    }
  }
  fail('Aucun titre dans la barre du haut.');
}

String _topBarTitle(WidgetTester tester) => _topBarText(tester).data!;

class _EmptyStore implements ConversationStore {
  @override
  Future<List<ChatConversation>> load() async => <ChatConversation>[];

  @override
  Future<void> save(List<ChatConversation> conversations) async {}

  @override
  Future<void> clear() async {}
}

class _ShortAnswerBackend implements LocalLlmBackend {
  @override
  String get id => 'short';

  @override
  String get displayName => 'Backend de test';

  @override
  String? get loadedModelPath => '/models/test.gguf';

  @override
  Future<String> get nativeVersion async => 'short/0.0.0';

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
  }) => Stream<String>.value('ok');

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _LongAnswerBackend implements LocalLlmBackend {
  @override
  String get id => 'long';

  @override
  String get displayName => 'Backend de test';

  @override
  String? get loadedModelPath => '/models/test.gguf';

  @override
  Future<String> get nativeVersion async => 'long/0.0.0';

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
    // Réponse assez longue pour dépasser la hauteur de l'écran.
    final lines = List<String>.generate(60, (i) => 'Ligne de réponse $i');
    return Stream<String>.value(lines.join('\n'));
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
