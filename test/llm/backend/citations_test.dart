// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/storage/api_key_store.dart';
import 'package:foxllm/llm/backend/gemini_backend.dart';
import 'package:foxllm/llm/backend/openai_compatible_backend.dart';
import 'package:foxllm/llm/backend/openai_responses_backend.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/personal_api/provider_config.dart';
import 'package:http/http.dart' as http;

const _openAi = ProviderConfig(
  id: 'openai',
  displayName: 'OpenAI',
  baseUrl: 'https://api.openai.com/v1',
  model: 'gpt-5',
);

void main() {
  group('OpenAI Responses', () {
    test('relève les sources annoncées pendant le flux', () async {
      final backend = OpenAiResponsesBackend(
        provider: _openAi,
        keyStore: _FakeApiKeyStore(),
        clientFactory: () => _SseClient(const <String>[
          'data: {"type":"response.output_text.delta","delta":"D’après "}',
          '',
          // Forme de l'API Responses : adresse et titre à plat.
          'data: {"type":"response.output_text.annotation.added",'
              '"annotation":{"type":"url_citation",'
              '"url":"https://exemple.fr/a","title":"Article A"}}',
          '',
          'data: {"type":"response.output_text.delta","delta":"deux sources."}',
          '',
          'data: {"type":"response.output_text.annotation.added",'
              '"annotation":{"type":"url_citation",'
              '"url":"https://exemple.fr/b","title":"Article B"}}',
          '',
          // Répétition du même lien : elle ne doit pas créer de doublon.
          'data: {"type":"response.output_text.annotation.added",'
              '"annotation":{"type":"url_citation",'
              '"url":"https://exemple.fr/a","title":"Article A"}}',
          '',
          'data: [DONE]',
          '',
        ]),
      );
      addTearDown(backend.dispose);

      final text = await backend
          .generate(messages: <ChatMessage>[const ChatMessage.user('?')])
          .join();

      expect(text, 'D’après deux sources.');
      expect(backend.citations.map((citation) => citation.url), <String>[
        'https://exemple.fr/a',
        'https://exemple.fr/b',
      ]);
      expect(backend.citations.first.title, 'Article A');
    });

    test('accepte aussi la forme imbriquée de chat/completions', () async {
      final backend = OpenAiResponsesBackend(
        provider: _openAi,
        keyStore: _FakeApiKeyStore(),
        clientFactory: () => _SseClient(const <String>[
          'data: {"type":"response.output_text.annotation.added",'
              '"annotation":{"type":"url_citation","url_citation":'
              '{"url":"https://exemple.fr/c","title":"Article C"}}}',
          '',
          'data: [DONE]',
          '',
        ]),
      );
      addTearDown(backend.dispose);

      await backend
          .generate(messages: <ChatMessage>[const ChatMessage.user('?')])
          .drain<void>();

      expect(backend.citations.single.url, 'https://exemple.fr/c');
      expect(backend.citations.single.title, 'Article C');
    });

    test('une annotation d’un autre type est ignorée', () async {
      final backend = OpenAiResponsesBackend(
        provider: _openAi,
        keyStore: _FakeApiKeyStore(),
        clientFactory: () => _SseClient(const <String>[
          'data: {"type":"response.output_text.annotation.added",'
              '"annotation":{"type":"file_citation","file_id":"f-1"}}',
          '',
          'data: [DONE]',
          '',
        ]),
      );
      addTearDown(backend.dispose);

      await backend
          .generate(messages: <ChatMessage>[const ChatMessage.user('?')])
          .drain<void>();

      expect(backend.citations, isEmpty);
    });

    test('les sources d’une réponse ne survivent pas à la suivante', () async {
      var first = true;
      final backend = OpenAiResponsesBackend(
        provider: _openAi,
        keyStore: _FakeApiKeyStore(),
        clientFactory: () {
          final events = first
              ? const <String>[
                  'data: {"type":"response.output_text.annotation.added",'
                      '"annotation":{"type":"url_citation",'
                      '"url":"https://exemple.fr/a"}}',
                  '',
                  'data: [DONE]',
                  '',
                ]
              : const <String>['data: [DONE]', ''];
          first = false;
          return _SseClient(events);
        },
      );
      addTearDown(backend.dispose);

      await backend
          .generate(messages: <ChatMessage>[const ChatMessage.user('1')])
          .drain<void>();
      expect(backend.citations, hasLength(1));

      await backend
          .generate(messages: <ChatMessage>[const ChatMessage.user('2')])
          .drain<void>();
      expect(
        backend.citations,
        isEmpty,
        reason: 'les sources appartiennent à la réponse en cours',
      );
    });
  });

  group('Gemini', () {
    test('relève les métadonnées d’ancrage', () async {
      final backend = GeminiBackend(
        model: 'gemini-2.5-flash',
        keyStore: _FakeApiKeyStore(),
        apiKeyPersistence: ApiKeyPersistence.device,
        clientFactory: () => _SseClient(<String>[
          'data: ${jsonEncode(<String, Object?>{
            'candidates': <Object?>[
              <String, Object?>{
                'content': <String, Object?>{
                  'parts': <Object?>[
                    <String, Object?>{'text': 'Réponse ancrée.'},
                  ],
                },
                'groundingMetadata': <String, Object?>{
                  'groundingChunks': <Object?>[
                    <String, Object?>{
                      'web': <String, Object?>{'uri': 'https://exemple.fr/g', 'title': 'Page G'},
                    },
                    // Entrée sans adresse : elle est écartée.
                    <String, Object?>{
                      'web': <String, Object?>{'title': 'Sans lien'},
                    },
                  ],
                },
              },
            ],
          })}',
          '',
        ]),
      );
      addTearDown(backend.dispose);

      final text = await backend
          .generate(messages: <ChatMessage>[const ChatMessage.user('?')])
          .join();

      expect(text, 'Réponse ancrée.');
      expect(backend.citations.single.url, 'https://exemple.fr/g');
      expect(backend.citations.single.title, 'Page G');
    });
  });

  group('fournisseur sans recherche', () {
    test('un moteur chat/completions ne cite rien', () async {
      final backend = OpenAiCompatibleBackend(
        provider: const ProviderConfig(
          id: 'groq',
          displayName: 'Groq',
          baseUrl: 'https://api.groq.com/openai/v1',
          model: 'llama',
        ),
        keyStore: _FakeApiKeyStore(),
        clientFactory: () => _SseClient(const <String>[
          'data: {"choices":[{"delta":{"content":"Salut"}}]}',
          '',
          'data: [DONE]',
          '',
        ]),
      );
      addTearDown(backend.dispose);

      await backend
          .generate(messages: <ChatMessage>[const ChatMessage.user('?')])
          .drain<void>();

      expect(backend.citations, isEmpty);
    });
  });
}

class _SseClient extends http.BaseClient {
  _SseClient(this.events);

  final List<String> events;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('${events.join('\n')}\n')),
      200,
    );
  }
}

class _FakeApiKeyStore extends ApiKeyStore {
  @override
  Future<String?> read({
    required String providerId,
    required ApiKeyPersistence persistence,
  }) async => 'secret';
}
