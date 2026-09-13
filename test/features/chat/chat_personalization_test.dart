// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxgpt/core/llm/chat_message.dart';
import 'package:foxgpt/core/llm/generation_settings.dart';
import 'package:foxgpt/core/llm/local_backend_provider.dart';
import 'package:foxgpt/core/llm/local_llm_backend.dart';
import 'package:foxgpt/core/llm/personalization.dart';
import 'package:foxgpt/features/chat/chat_conversation.dart';
import 'package:foxgpt/features/chat/chat_screen.dart';
import 'package:foxgpt/features/chat/conversation_store.dart';
import 'package:foxgpt_native/foxgpt_native.dart';

void main() {
  testWidgets('les instructions personnalisées ouvrent chaque requête', (
    tester,
  ) async {
    final backend = _FakeBackend();
    await _pumpChat(
      tester,
      backend,
      instructions: 'Réponds en trois phrases maximum.',
    );

    await _send(tester, 'Bonjour');
    await tester.pumpAndSettle();

    final request = backend.generateCalls.single;
    expect(request.first.role, ChatRole.system);
    expect(request.first.content, 'Réponds en trois phrases maximum.');
    expect(request[1].role, ChatRole.user);
    expect(request[1].content, 'Bonjour');

    // Toujours en tête au tour suivant, pas empilées.
    await _send(tester, 'Et ensuite ?');
    await tester.pumpAndSettle();

    final second = backend.generateCalls.last;
    expect(second.where((m) => m.role == ChatRole.system), hasLength(1));
    expect(second.first.role, ChatRole.system);
  });

  testWidgets('sans instruction, aucun message système n’est envoyé', (
    tester,
  ) async {
    final backend = _FakeBackend();
    await _pumpChat(tester, backend);

    await _send(tester, 'Bonjour');
    await tester.pumpAndSettle();

    expect(
      backend.generateCalls.single.where((m) => m.role == ChatRole.system),
      isEmpty,
    );
  });

  testWidgets('les instructions ne sont pas figées dans la conversation', (
    tester,
  ) async {
    // Elles sont globales et modifiables : une conversation enregistrée avec
    // les consignes du jour les rejouerait indéfiniment.
    final store = _RecordingStore();
    final backend = _FakeBackend();
    await _pumpChat(
      tester,
      backend,
      instructions: 'Sois concis.',
      store: store,
    );

    await _send(tester, 'Bonjour');
    await tester.pumpAndSettle();

    expect(
      store.lastSaved.single.messages.where((m) => m.role == ChatRole.system),
      isEmpty,
    );
    expect(store.lastSaved.single.messages.first.content, 'Bonjour');
    // Rien de visible non plus dans le fil.
    expect(find.text('Sois concis.'), findsNothing);
  });
}

Future<void> _pumpChat(
  WidgetTester tester,
  _FakeBackend backend, {
  String instructions = '',
  ConversationStore? store,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localLlmBackendProvider.overrideWithValue(backend),
        conversationStoreProvider.overrideWithValue(store ?? _RecordingStore()),
        personalizationStoreProvider.overrideWithValue(
          _MemoryStore(instructions),
        ),
      ],
      child: const MaterialApp(home: ChatScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byTooltip('Envoyer'));
  await tester.pump();
}

class _MemoryStore extends PersonalizationStore {
  _MemoryStore(this.stored);

  String stored;

  @override
  Future<String> load() async => stored;

  @override
  Future<void> save(String instructions) async => stored = instructions.trim();
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
  final List<List<ChatMessage>> generateCalls = <List<ChatMessage>>[];

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
  Future<FoxGptModelInfo?> get modelInfo async => null;

  @override
  Future<FoxGptGenerationStats?> get lastGenerationStats async => null;

  @override
  Future<void> loadModel(String path) async {}

  @override
  Future<void> unloadModel() async {}

  @override
  Stream<String> generate({
    required List<ChatMessage> messages,
    GenerationSettings settings = const GenerationSettings(),
  }) {
    generateCalls.add(List<ChatMessage>.of(messages));
    return Stream<String>.value('ok');
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
