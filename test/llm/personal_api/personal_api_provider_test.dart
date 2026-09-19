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

  group('catalogue des fournisseurs', () {
    test('la liste est par ordre alphabétique', () {
      final names = personalApiProviders
          .map((provider) => provider.displayName)
          .toList();

      expect(names, <String>[
        'Anthropic',
        'DeepSeek',
        'Google',
        'Groq',
        'Mistral AI',
        'OpenAI',
        'OpenRouter',
        'Personnalisé',
        'xAI',
      ]);

      // Et cet ordre est bien celui d'un tri, pas une liste écrite à la main
      // qui se déferait au prochain ajout.
      final sorted = List<String>.of(names)
        ..sort(
          (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
        );
      expect(names, sorted);
    });

    test('les deux nouveaux fournisseurs se résolvent par identifiant', () {
      expect(
        personalApiProviderById('anthropic'),
        same(anthropicPersonalApiProvider),
      );
      expect(
        personalApiProviderById('deepseek'),
        same(deepSeekPersonalApiProvider),
      );
      expect(
        anthropicPersonalApiProvider.protocol,
        PersonalApiProtocol.anthropic,
      );
      expect(
        deepSeekPersonalApiProvider.protocol,
        PersonalApiProtocol.openAiCompatible,
      );
    });

    test('une base URL connue retrouve son fournisseur', () {
      expect(
        inferPersonalApiProvider('https://api.anthropic.com/v1'),
        same(anthropicPersonalApiProvider),
      );
      expect(
        inferPersonalApiProvider('https://api.deepseek.com/v1'),
        same(deepSeekPersonalApiProvider),
      );
    });

    test('seuls OpenAI et Google annoncent la recherche web', () {
      final searching = personalApiProviders
          .where((provider) => provider.supportsWebSearch)
          .map((provider) => provider.id)
          .toList();

      // Anthropic a bien un outil de recherche, mais FoxLLM ne le déclare pas
      // encore dans ses requêtes : l'annoncer promettrait des sources qui ne
      // viendraient jamais.
      expect(searching, <String>['gemini', 'openai']);
    });
  });

  test(
    'Anthropic model discovery uses x-api-key and the API version',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/models');
        expect(request.headers['x-api-key'], 'secret');
        expect(request.headers['anthropic-version'], anthropicApiVersion);
        expect(request.headers['Authorization'], isNull);
        return http.Response(
          '{"data":['
          '{"type":"model","id":"claude-example","display_name":"Claude"},'
          '{"type":"model","id":"claude-autre"}'
          ']}',
          200,
        );
      });

      final models = await fetchPersonalApiModels(
        provider: anthropicPersonalApiProvider,
        apiKey: 'secret',
        client: client,
      );

      expect(models, <String>['claude-autre', 'claude-example']);
    },
  );

  test('DeepSeek discovery passe par le format OpenAI', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://api.deepseek.com/v1/models');
      expect(request.headers['Authorization'], 'Bearer secret');
      return http.Response(
        '{"data":[{"id":"deepseek-chat"},{"id":"deepseek-reasoner"}]}',
        200,
      );
    });

    final models = await fetchPersonalApiModels(
      provider: deepSeekPersonalApiProvider,
      apiKey: 'secret',
      client: client,
    );

    expect(models, <String>['deepseek-chat', 'deepseek-reasoner']);
  });

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
