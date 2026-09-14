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
  testWidgets('l’arrière-plan pendant la relecture n’efface pas l’historique', (
    tester,
  ) async {
    final store = _SlowStore(_oneConversation());
    await _pumpChat(tester, store);

    // La lecture n'est pas revenue : la liste en mémoire est encore vide.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    store.completeLoad();
    await tester.pumpAndSettle();

    expect(
      store.savedEmpty,
      isFalse,
      reason: 'un historique vide a été écrit par-dessus le fichier existant',
    );
  });

  testWidgets('un envoi pendant la relecture ne perd ni l’un ni l’autre', (
    tester,
  ) async {
    final store = _SlowStore(_oneConversation());
    await _pumpChat(tester, store);

    await tester.enterText(find.byType(TextField).first, 'Nouvelle question');
    await tester.pump();
    await tester.tap(find.byTooltip('Envoyer'));
    await tester.pump();

    store.completeLoad();
    await tester.pumpAndSettle();

    // L'ancien fil et le nouveau coexistent : ni la relecture n'écrase
    // l'envoi, ni l'envoi n'ampute l'historique relu.
    final titles = store.lastSaved.map((c) => c.title).toList();
    expect(titles, contains('Ancienne conversation'));
    expect(titles, contains('Nouvelle question'));
  });

  testWidgets('une lecture en échec n’autorise aucune écriture', (
    tester,
  ) async {
    final store = _SlowStore(_oneConversation(), failLoad: true);
    await _pumpChat(tester, store);

    store.completeLoad();
    await tester.pumpAndSettle();

    // Le fichier existe toujours sur disque : sa liste ne doit pas être
    // remplacée par la liste vide que l'écran a en mémoire.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(store.saveCalls, isEmpty);
    expect(find.textContaining('historique'), findsWidgets);
  });

  testWidgets('fermer l’écran pendant la relecture n’efface rien', (
    tester,
  ) async {
    final store = _SlowStore(_oneConversation());
    await _pumpChat(tester, store);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    store.completeLoad();
    await tester.pumpAndSettle();

    expect(store.savedEmpty, isFalse);
    expect(tester.takeException(), isNull);
  });
}

List<ChatConversation> _oneConversation() => <ChatConversation>[
  ChatConversation(
    id: 1,
    title: 'Ancienne conversation',
    updatedAt: DateTime.now(),
    messages: <ChatMessage>[
      const ChatMessage.user('Ancienne question'),
      const ChatMessage.assistant('Ancienne réponse'),
    ],
  ),
];

Future<void> _pumpChat(WidgetTester tester, _SlowStore store) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localLlmBackendProvider.overrideWithValue(_ScriptedBackend()),
        conversationStoreProvider.overrideWithValue(store),
      ],
      child: const MaterialApp(home: ChatScreen()),
    ),
  );
  await tester.pump();
}

/// Magasin dont la lecture ne revient que lorsque le test le décide.
class _SlowStore implements ConversationStore {
  _SlowStore(this.seed, {this.failLoad = false});

  final List<ChatConversation> seed;
  final bool failLoad;
  final _gate = Completer<void>();

  final List<List<ChatConversation>> saveCalls = <List<ChatConversation>>[];

  List<ChatConversation> get lastSaved => saveCalls.last;

  /// Vrai si une écriture a remplacé le fichier par une liste vide.
  bool get savedEmpty => saveCalls.any((saved) => saved.isEmpty);

  void completeLoad() => _gate.complete();

  @override
  Future<List<ChatConversation>> load() async {
    await _gate.future;
    if (failLoad) {
      throw StateError('fichier illisible');
    }
    return seed;
  }

  @override
  Future<void> save(List<ChatConversation> conversations) async {
    saveCalls.add(List<ChatConversation>.of(conversations));
  }

  @override
  Future<void> clear() async {}
}

class _ScriptedBackend implements LocalLlmBackend {
  @override
  String get id => 'scripted';

  @override
  String get displayName => 'Backend de test';

  @override
  String? get loadedModelPath => '/models/test.gguf';

  @override
  Future<String> get nativeVersion async => 'scripted/0.0.0';

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
