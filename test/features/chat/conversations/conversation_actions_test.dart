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

void main() {
  testWidgets('renomme une conversation depuis le menu latéral', (
    tester,
  ) async {
    final store = _RecordingStore();
    await _pumpChat(tester, store);
    await _createConversation(tester, 'Ma question');

    await _openActions(tester, 'Ma question');
    await tester.tap(find.text('Renommer'));
    await tester.pumpAndSettle();

    await tester.enterText(_renameField, 'Recette de tarte');
    await tester.tap(find.widgetWithText(FilledButton, 'Renommer'));
    await tester.pumpAndSettle();

    // Seul le titre change : le message d'origine reste dans le fil. Le
    // nouveau nom se lit en haut de l'écran comme dans le menu latéral.
    expect(find.text('Recette de tarte'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('chat-content')),
        matching: find.text('Ma question'),
      ),
      findsOneWidget,
    );
    expect(store.lastSaved.single.title, 'Recette de tarte');
    expect(store.lastSaved.single.messages.first.content, 'Ma question');
    expect(tester.takeException(), isNull);
  });

  testWidgets('un nom vide laisse le titre inchangé', (tester) async {
    final store = _RecordingStore();
    await _pumpChat(tester, store);
    await _createConversation(tester, 'Ma question');

    await _openActions(tester, 'Ma question');
    await tester.tap(find.text('Renommer'));
    await tester.pumpAndSettle();

    await tester.enterText(_renameField, '   ');
    await tester.tap(find.widgetWithText(FilledButton, 'Renommer'));
    await tester.pumpAndSettle();

    expect(find.text('Ma question'), findsWidgets);
  });

  testWidgets('supprime une conversation après confirmation', (tester) async {
    final store = _RecordingStore();
    await _pumpChat(tester, store);
    await _createConversation(tester, 'À supprimer');

    await _openActions(tester, 'À supprimer');
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();

    expect(find.text('Supprimer la conversation ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await tester.pumpAndSettle();

    expect(find.text('À supprimer'), findsNothing);
    expect(find.text('Aucune conversation'), findsOneWidget);
    expect(store.lastSaved, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('annuler la suppression conserve la conversation', (
    tester,
  ) async {
    final store = _RecordingStore();
    await _pumpChat(tester, store);
    await _createConversation(tester, 'À garder');

    await _openActions(tester, 'À garder');
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
    await tester.pumpAndSettle();

    expect(find.text('À garder'), findsWidgets);
  });

  testWidgets('supprimer la conversation active vide le fil', (tester) async {
    final store = _RecordingStore();
    await _pumpChat(tester, store);
    await _createConversation(tester, 'Conversation active');

    // Le fil affiche bien la conversation avant suppression.
    expect(find.text('Conversation active'), findsWidgets);

    await _openActions(tester, 'Conversation active');
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await tester.pumpAndSettle();

    // Retour à l'accueil : plus aucun message affiché.
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Aucune conversation'), findsOneWidget);
  });
}

Future<void> _pumpChat(WidgetTester tester, _RecordingStore store) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localLlmBackendProvider.overrideWithValue(_FakeBackend()),
        conversationStoreProvider.overrideWithValue(store),
      ],
      child: const MaterialApp(home: ChatScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _createConversation(WidgetTester tester, String message) async {
  await tester.enterText(find.byType(TextField).first, message);
  await tester.pump();
  await tester.tap(find.byTooltip('Envoyer'));
  await tester.pumpAndSettle();
}

/// Champ du dialogue de renommage, repéré par son texte d'aide.
final Finder _renameField = find.ancestor(
  of: find.text('Nom de la conversation'),
  matching: find.byType(TextField),
);

Future<void> _openActions(WidgetTester tester, String title) async {
  await tester.tap(find.byTooltip('Menu'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Actions de la conversation').first);
  await tester.pumpAndSettle();
}

class _RecordingStore implements ConversationStore {
  List<ChatConversation> lastSaved = <ChatConversation>[];

  @override
  Future<List<ChatConversation>> load() async => <ChatConversation>[];

  @override
  Future<void> save(List<ChatConversation> conversations) async {
    lastSaved = List<ChatConversation>.of(conversations);
  }

  @override
  Future<void> clear() async => lastSaved = <ChatConversation>[];
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
