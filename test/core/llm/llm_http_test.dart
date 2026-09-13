// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:foxgpt/core/llm/chat_message.dart';
import 'package:foxgpt/core/llm/gemini_backend.dart';
import 'package:foxgpt/core/llm/llm_http.dart';
import 'package:foxgpt/core/llm/openai_compatible_backend.dart';
import 'package:foxgpt/core/llm/provider_config.dart';
import 'package:foxgpt/core/security/api_key_store.dart';
import 'package:http/http.dart' as http;

void main() {
  const provider = ProviderConfig(
    id: 'test',
    displayName: 'Test Provider',
    baseUrl: 'https://example.com/v1',
    model: 'test-model',
    apiKeyPersistence: ApiKeyPersistence.session,
  );

  const messages = <ChatMessage>[ChatMessage.user('Bonjour')];

  group('sseDataPayload', () {
    test('extrait la charge utile avec ou sans espace après "data:"', () {
      expect(sseDataPayload('data: {"a":1}'), '{"a":1}');
      expect(sseDataPayload('data:{"a":1}'), '{"a":1}');
      expect(sseDataPayload('data: [DONE]'), '[DONE]');
    });

    test('ignore les lignes qui ne portent pas de données', () {
      expect(sseDataPayload(''), isNull);
      expect(sseDataPayload(': heartbeat OpenRouter'), isNull);
      expect(sseDataPayload('event: message'), isNull);
      expect(sseDataPayload('id: 42'), isNull);
      expect(sseDataPayload('data:'), isNull);
      expect(sseDataPayload('data:    '), isNull);
    });
  });

  group('HttpStreamingBackend (socle partagé)', () {
    test('ignore commentaires, heartbeats et fragments sans texte', () async {
      const payload =
          ': ping\n\n'
          'event: message\n'
          'data: {"choices":[{"delta":{"content":"Bon"}}]}\n\n'
          'data: {"choices":[]}\n\n'
          'data: {"choices":[{"delta":{}}]}\n\n'
          'data: {"choices":[{"delta":{"role":"assistant"}}]}\n\n'
          'data: {"choices":[{"delta":{"content":"jour"}}]}\n\n'
          'data: [DONE]\n\n'
          'data: {"choices":[{"delta":{"content":"après la fin"}}]}\n\n';

      final backend = OpenAiCompatibleBackend(
        provider: provider,
        keyStore: _StaticApiKeyStore('secret'),
        clientFactory: () => _ScriptedClient(payload),
      );

      expect(await backend.generate(messages: messages).join(), 'Bonjour');
      await backend.dispose();
    });

    test(
      'remonte une PersonalApiHttpException sur une réponse non 2xx',
      () async {
        final backend = OpenAiCompatibleBackend(
          provider: provider,
          keyStore: _StaticApiKeyStore('secret'),
          clientFactory: () => _ScriptedClient('{"error":"nope"}', status: 429),
        );

        await expectLater(
          backend.generate(messages: messages).drain<void>(),
          throwsA(
            isA<PersonalApiHttpException>()
                .having((error) => error.statusCode, 'statusCode', 429)
                .having((error) => error.body, 'body', '{"error":"nope"}'),
          ),
        );
        await backend.dispose();
      },
    );

    test('échoue clairement quand aucune clé API n’est enregistrée', () async {
      final backend = OpenAiCompatibleBackend(
        provider: provider,
        keyStore: _StaticApiKeyStore(null),
        clientFactory: () => _ScriptedClient(''),
      );

      await expectLater(
        backend.generate(messages: messages).drain<void>(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Aucune clé API configurée pour Test Provider.',
          ),
        ),
      );
      await backend.dispose();
    });

    test('Gemini hérite du même cycle de vie stop/dispose', () async {
      final backend = GeminiBackend(
        model: 'gemini-example',
        keyStore: _StaticApiKeyStore('secret'),
        apiKeyPersistence: ApiKeyPersistence.session,
        clientFactory: () => _ScriptedClient(''),
      );

      await backend.dispose();

      await expectLater(
        backend.generate(messages: messages).drain<void>(),
        throwsStateError,
      );
    });

    test('Gemini signale aussi l’absence de clé API', () async {
      final backend = GeminiBackend(
        model: 'gemini-example',
        keyStore: _StaticApiKeyStore('   '),
        apiKeyPersistence: ApiKeyPersistence.session,
        clientFactory: () => _ScriptedClient(''),
      );

      await expectLater(
        backend.generate(messages: messages).drain<void>(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Aucune clé API configurée pour Google Gemini.',
          ),
        ),
      );
      await backend.dispose();
    });
  });
}

class _StaticApiKeyStore extends ApiKeyStore {
  _StaticApiKeyStore(this._apiKey);

  final String? _apiKey;

  @override
  Future<String?> read({
    required String providerId,
    required ApiKeyPersistence persistence,
  }) async {
    return _apiKey;
  }
}

class _ScriptedClient extends http.BaseClient {
  _ScriptedClient(this._payload, {int status = 200}) : _status = status;

  final String _payload;
  final int _status;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(_payload)),
      _status,
    );
  }
}
