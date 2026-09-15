// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/storage/api_key_store.dart';
import 'package:foxllm/features/chat/chat_backend_host.dart';
import 'package:foxllm/features/chat/chat_screen.dart';
import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/features/chat/conversations/conversation_store.dart';
import 'package:foxllm/llm/backend/local_backend_provider.dart';
import 'package:foxllm/llm/backend/local_llm_backend.dart';
import 'package:foxllm/llm/backend/openai_responses_backend.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm/llm/personal_api/personal_api_chat_backend.dart';
import 'package:foxllm/llm/personal_api/personal_api_settings.dart';
import 'package:foxllm/llm/personal_api/provider_config.dart';
import 'package:foxllm_native/foxllm_native.dart';
import 'package:http/http.dart' as http;

/// Le chemin complet, sans faux moteur : le flux SSE traverse le backend HTTP
/// réel, l'adaptateur d'API personnelle réel, puis l'écran de chat. Seul le
/// transport est simulé.
void main() {
  testWidgets('un flux écourté sans aucun fragment remonte jusqu’au fil', (
    tester,
  ) async {
    final store = _RecordingStore();
    await _pumpChat(tester, store, <String>[
      'data: {"type":"response.created"}',
      'data: {"type":"response.incomplete","response":'
          '{"incomplete_details":{"reason":"max_output_tokens"}}}',
      'data: [DONE]',
    ]);

    await _send(tester, 'Ma question');

    // Le défaut d'origine : sans texte reçu, l'issue n'était pas lue, la
    // bulle disparaissait et la réponse passait pour une réussite.
    expect(find.textContaining('Aucun texte reçu'), findsOneWidget);
    expect(find.textContaining('limite de longueur'), findsOneWidget);

    final saved = store.saveCalls.last.single.messages.last;
    expect(saved.outcome, GenerationOutcome.incomplete);
    expect(saved.outcomeReason, 'max_output_tokens');
  });

  testWidgets('un flux écourté après du texte garde le texte et la raison', (
    tester,
  ) async {
    final store = _RecordingStore();
    await _pumpChat(tester, store, <String>[
      'data: {"type":"response.output_text.delta","delta":"Début de "}',
      'data: {"type":"response.output_text.delta","delta":"réponse"}',
      'data: {"type":"response.incomplete","response":'
          '{"incomplete_details":{"reason":"max_output_tokens"}}}',
      'data: [DONE]',
    ]);

    await _send(tester, 'Ma question');

    expect(find.textContaining('Réponse écourtée'), findsOneWidget);
    final saved = store.saveCalls.last.single.messages.last;
    expect(saved.content, 'Début de réponse');
    expect(saved.outcome, GenerationOutcome.incomplete);
  });

  testWidgets('un flux complet ne porte aucune mention', (tester) async {
    final store = _RecordingStore();
    await _pumpChat(tester, store, <String>[
      'data: {"type":"response.output_text.delta","delta":"Bonjour"}',
      'data: {"type":"response.completed"}',
      'data: [DONE]',
    ]);

    await _send(tester, 'Ma question');

    expect(find.textContaining('écourtée'), findsNothing);
    expect(find.textContaining('Aucun texte reçu'), findsNothing);
    final saved = store.saveCalls.last.single.messages.last;
    expect(saved.content, 'Bonjour');
    expect(saved.outcome, GenerationOutcome.complete);
  });

  testWidgets('une génération écourtée ne déteint pas sur la suivante', (
    tester,
  ) async {
    final store = _RecordingStore();
    await _pumpChat(tester, store, <String>[
      'data: {"type":"response.incomplete","response":'
          '{"incomplete_details":{"reason":"max_output_tokens"}}}',
      'data: [DONE]',
    ]);

    await _send(tester, 'Première question');
    expect(find.textContaining('Aucun texte reçu'), findsOneWidget);

    // La file s'est arrêtée là : c'est l'utilisateur qui relance.
    _ScriptedClient.script = <String>[
      'data: {"type":"response.output_text.delta","delta":"Suite"}',
      'data: {"type":"response.completed"}',
      'data: [DONE]',
    ];
    await _send(tester, 'Seconde question');

    final messages = store.saveCalls.last.single.messages;
    expect(messages.last.content, 'Suite');
    expect(messages.last.outcome, GenerationOutcome.complete);
    // La première mention reste où elle est, sur sa propre réponse.
    expect(find.textContaining('Aucun texte reçu'), findsOneWidget);
  });
}

// ---- utilitaires ----------------------------------------------------------

const _provider = ProviderConfig(
  id: 'openai',
  displayName: 'OpenAI',
  baseUrl: 'https://api.openai.com/v1',
  model: 'gpt-5',
);

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump();
  await tester.tap(find.byTooltip('Envoyer'));
  await tester.pump();
  // Le transport simulé reste un vrai client HTTP : ses événements ne
  // circulent qu'en dehors de l'horloge simulée de `testWidgets`.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await _settle(tester);
}

/// Avance sans attendre l'immobilité : l'indicateur d'une génération en cours
/// tourne sans fin.
Future<void> _settle(WidgetTester tester, [int frames = 40]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pumpChat(
  WidgetTester tester,
  _RecordingStore store,
  List<String> script,
) async {
  _ScriptedClient.script = script;
  final remote = OpenAiResponsesBackend(
    provider: _provider,
    keyStore: _FakeApiKeyStore(),
    clientFactory: _ScriptedClient.new,
  );
  final local = _IdleLocalBackend();
  final backend = PersonalApiChatBackend(
    settings: const PersonalApiSettings(
      providerId: 'openai',
      model: 'gpt-5',
      useInChat: true,
      hasApiKey: true,
    ),
    remoteBackend: remote,
    localBackend: local,
  );
  addTearDown(remote.dispose);

  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatBackendProvider.overrideWithValue(backend),
        localLlmBackendProvider.overrideWithValue(local),
        conversationStoreProvider.overrideWithValue(store),
      ],
      child: const MaterialApp(home: ChatScreen()),
    ),
  );
  await _settle(tester);
}

class _FakeApiKeyStore extends ApiKeyStore {
  @override
  Future<String?> read({
    required String providerId,
    required ApiKeyPersistence persistence,
  }) async => 'secret';
}

/// Flux SSE dicté par le test, servi sur un HTTP 200.
class _ScriptedClient extends http.BaseClient {
  static List<String> script = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = script.map((line) => '$line\n\n').join();
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      200,
    );
  }
}

class _RecordingStore implements ConversationStore {
  final List<List<ChatConversation>> saveCalls = <List<ChatConversation>>[];

  @override
  Future<List<ChatConversation>> load() async => <ChatConversation>[];

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

/// Moteur local inerte : l'adaptateur lui délègue ce qui ne concerne pas la
/// génération, mais rien ne passe par lui ici.
class _IdleLocalBackend implements LocalLlmBackend {
  @override
  String get id => 'local';

  @override
  String get displayName => 'Modèle local';

  @override
  String? get loadedModelPath => null;

  @override
  Future<String> get nativeVersion async => 'test/0.0.0';

  @override
  Future<bool> get isModelLoaded async => false;

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
  }) => const Stream<String>.empty();

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
