// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/llm/chat_message.dart';
import 'package:foxllm/core/llm/generation_settings.dart';
import 'package:foxllm/core/llm/openai_responses_backend.dart';
import 'package:foxllm/core/llm/personal_api_provider.dart';
import 'package:foxllm/core/llm/personal_api_settings.dart';
import 'package:foxllm/core/llm/provider_config.dart';
import 'package:foxllm/core/security/api_key_store.dart';
import 'package:http/http.dart' as http;

const _provider = ProviderConfig(
  id: 'openai',
  displayName: 'OpenAI',
  baseUrl: 'https://api.openai.com/v1',
  model: 'gpt-5',
);

void main() {
  group('requête Responses', () {
    test('adresse le point d’entrée responses', () {
      final request = _request();
      expect(request.url.toString(), 'https://api.openai.com/v1/responses');
      expect(request.headers['Authorization'], 'Bearer clé');
      expect(request.headers['Accept'], 'text/event-stream');
    });

    test('la consigne système a son champ dédié', () {
      final body = _body(
        messages: <ChatMessage>[
          const ChatMessage.system('Sois concis.'),
          const ChatMessage.user('Bonjour'),
        ],
      );

      expect(body['instructions'], 'Sois concis.');
      // Elle ne doit pas rejoindre les tours de conversation.
      final input = body['input']! as List<Object?>;
      expect(input, hasLength(1));
      expect((input.single as Map)['role'], 'user');
      expect((input.single as Map)['content'], 'Bonjour');
    });

    test('l’historique garde ses rôles', () {
      final body = _body(
        messages: <ChatMessage>[
          const ChatMessage.user('Premier'),
          const ChatMessage.assistant('Réponse'),
          const ChatMessage.user('Second'),
        ],
      );

      final input = (body['input']! as List<Object?>)
          .cast<Map<Object?, Object?>>();
      expect(input.map((item) => item['role']), <String>[
        'user',
        'assistant',
        'user',
      ]);
    });

    test('les limites de génération portent leurs noms Responses', () {
      final body = _body(
        settings: const GenerationSettings(maxTokens: 1536, temperature: 0.4),
      );

      expect(body['max_output_tokens'], 1536);
      expect(body['temperature'], 0.4);
      expect(body['stream'], isTrue);
      expect(body.containsKey('max_tokens'), isFalse);
    });

    test('l’outil de recherche n’est envoyé que si le mode est actif', () {
      expect(_body()['tools'], isNull);
      expect(
        _body(settings: const GenerationSettings(webSearch: true))['tools'],
        <Object>[
          <String, Object>{'type': 'web_search'},
        ],
      );
    });

    test('une image devient un morceau d’entrée', () {
      final body = _body(
        messages: <ChatMessage>[
          ChatMessage(
            role: ChatRole.user,
            content: 'Décris',
            images: <InlineImage>[
              InlineImage(
                mimeType: 'image/png',
                bytes: Uint8List.fromList(<int>[1, 2, 3]),
              ),
            ],
          ),
        ],
      );

      final parts =
          ((body['input']! as List<Object?>).single as Map)['content']
              as List<Object?>;
      expect((parts.first as Map)['type'], 'input_text');
      expect((parts.last as Map)['type'], 'input_image');
      expect(
        (parts.last as Map)['image_url'],
        startsWith('data:image/png;base64,'),
      );
    });
  });

  group('lecture du flux', () {
    test('ne retient que les fragments de texte', () {
      final backend = _backend();

      expect(
        backend.extractDeltas(<String, dynamic>{
          'type': 'response.output_text.delta',
          'delta': 'Salut ',
        }),
        <String>['Salut '],
      );
      // Les autres évènements du flux sont nombreux et sans texte.
      for (final type in <String>[
        'response.created',
        'response.output_item.added',
        'response.web_search_call.in_progress',
        'response.completed',
      ]) {
        expect(
          backend.extractDeltas(<String, dynamic>{'type': type}),
          isEmpty,
          reason: '$type ne porte pas de texte',
        );
      }
      expect(
        backend.extractDeltas(<String, dynamic>{
          'type': 'response.output_text.delta',
          'delta': '',
        }),
        isEmpty,
      );
    });

    test('streame une réponse de bout en bout', () async {
      final backend = OpenAiResponsesBackend(
        provider: _provider,
        keyStore: _FakeApiKeyStore(),
        clientFactory: _ResponsesClient.new,
      );
      addTearDown(backend.dispose);

      expect(
        await backend
            .generate(messages: <ChatMessage>[const ChatMessage.user('Salut')])
            .join(),
        'Bonjour toi !',
      );
    });
  });

  group('routage du fournisseur', () {
    test('OpenAI parle Responses, les autres chat/completions', () {
      expect(
        openAiPersonalApiProvider.protocol,
        PersonalApiProtocol.openAiResponses,
      );
      expect(
        groqPersonalApiProvider.protocol,
        PersonalApiProtocol.openAiCompatible,
      );

      final backend = createPersonalApiRemoteBackend(
        settings: const PersonalApiSettings(
          providerId: 'openai',
          model: 'gpt-5',
        ),
        keyStore: _FakeApiKeyStore(),
      );
      addTearDown(backend.dispose);
      expect(backend, isA<OpenAiResponsesBackend>());
    });

    test('la recherche web suit le protocole du fournisseur', () {
      expect(openAiPersonalApiProvider.supportsWebSearch, isTrue);
      expect(geminiPersonalApiProvider.supportsWebSearch, isTrue);
      for (final provider in <PersonalApiProvider>[
        groqPersonalApiProvider,
        mistralPersonalApiProvider,
        openRouterPersonalApiProvider,
        xAiPersonalApiProvider,
        customPersonalApiProvider,
      ]) {
        expect(
          provider.supportsWebSearch,
          isFalse,
          reason: '${provider.displayName} n’a pas d’outil de recherche',
        );
      }
    });
  });
}

OpenAiResponsesBackend _backend() =>
    OpenAiResponsesBackend(provider: _provider, keyStore: _FakeApiKeyStore());

http.Request _request({
  List<ChatMessage>? messages,
  GenerationSettings settings = const GenerationSettings(),
}) => _backend().buildRequest(
  apiKey: 'clé',
  messages: messages ?? <ChatMessage>[const ChatMessage.user('Bonjour')],
  settings: settings,
);

Map<String, Object?> _body({
  List<ChatMessage>? messages,
  GenerationSettings settings = const GenerationSettings(),
}) =>
    jsonDecode(_request(messages: messages, settings: settings).body)
        as Map<String, Object?>;

class _FakeApiKeyStore extends ApiKeyStore {
  @override
  Future<String?> read({
    required String providerId,
    required ApiKeyPersistence persistence,
  }) async => 'secret';
}

class _ResponsesClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    expect(request.url.toString(), 'https://api.openai.com/v1/responses');

    const events = <String>[
      'event: response.created',
      'data: {"type":"response.created"}',
      '',
      'data: {"type":"response.output_text.delta","delta":"Bonjour "}',
      '',
      'data: {"type":"response.output_text.delta","delta":"toi !"}',
      '',
      'data: {"type":"response.completed"}',
      '',
      'data: [DONE]',
      '',
    ];

    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('${events.join('\n')}\n')),
      200,
    );
  }
}
