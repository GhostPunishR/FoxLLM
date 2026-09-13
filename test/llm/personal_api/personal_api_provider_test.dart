// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/llm/personal_api/personal_api_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'OpenAI model discovery uses the preset URL and filters non-chat models',
    () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://api.openai.com/v1/models');
        expect(request.headers['Authorization'], 'Bearer secret');
        return http.Response(
          '{"data":['
          '{"id":"gpt-example"},'
          '{"id":"text-embedding-example"},'
          '{"id":"whisper-example"}'
          ']}',
          200,
        );
      });

      final models = await fetchPersonalApiModels(
        provider: openAiPersonalApiProvider,
        apiKey: 'secret',
        client: client,
      );

      expect(models, <String>['gpt-example']);
    },
  );

  test('Mistral model discovery keeps chat-capable models', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://api.mistral.ai/v1/models');
      return http.Response(
        '{"data":['
        '{"id":"mistral-chat","capabilities":{"completion_chat":true}},'
        '{"id":"mistral-embed","capabilities":{"completion_chat":false}}'
        ']}',
        200,
      );
    });

    final models = await fetchPersonalApiModels(
      provider: mistralPersonalApiProvider,
      apiKey: 'secret',
      client: client,
    );

    expect(models, <String>['mistral-chat']);
  });

  test(
    'Gemini model discovery uses x-goog-api-key and generateContent models',
    () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000',
        );
        expect(request.headers['x-goog-api-key'], 'secret');
        return http.Response(
          '{"models":['
          '{"name":"models/gemini-chat","supportedGenerationMethods":["generateContent"]},'
          '{"name":"models/gemini-embed","supportedGenerationMethods":["embedContent"]}'
          ']}',
          200,
        );
      });

      final models = await fetchPersonalApiModels(
        provider: geminiPersonalApiProvider,
        apiKey: 'secret',
        client: client,
      );

      expect(models, <String>['gemini-chat']);
    },
  );

  test('xAI discovery uses the language models endpoint', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://api.x.ai/v1/language-models');
      return http.Response('{"models":[{"id":"grok-example"}]}', 200);
    });

    final models = await fetchPersonalApiModels(
      provider: xAiPersonalApiProvider,
      apiKey: 'secret',
      client: client,
    );

    expect(models, <String>['grok-example']);
  });
}
