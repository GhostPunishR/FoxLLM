// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/storage/api_key_store.dart';
import 'package:foxllm/llm/backend/anthropic_backend.dart';
import 'package:foxllm/llm/backend/llm_http.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm/llm/personal_api/personal_api_provider.dart';
import 'package:foxllm/llm/personal_api/provider_config.dart';
import 'package:http/http.dart' as http;

/// L'API Messages d'Anthropic ne ressemble à aucune des deux autres : clé dans
/// `x-api-key`, version exigée, consignes système hors des messages, et un flux
/// d'évènements nommés.
void main() {
  group('la requête', () {
    test('porte la clé, la version, et aucun réglage d’échantillonnage', () {
      final request = _request(<ChatMessage>[
        const ChatMessage.user('Bonjour'),
      ]);

      expect(request.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(request.headers['x-api-key'], 'secret');
      expect(request.headers['anthropic-version'], anthropicApiVersion);
      expect(request.headers['Authorization'], isNull);

      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['model'], 'claude-example');
      expect(body['stream'], isTrue);
      expect(body['max_tokens'], isA<int>());
      // Les modèles récents d'Anthropic refusent ces deux réglages par une
      // erreur 400 : les envoyer rendrait le fournisseur inutilisable.
      expect(body.containsKey('temperature'), isFalse);
      expect(body.containsKey('top_p'), isFalse);
    });

    test('sort les consignes système des messages', () {
      final request = _request(<ChatMessage>[
        const ChatMessage.system('Tu réponds en français.'),
        const ChatMessage.user('Bonjour'),
        const ChatMessage.assistant('Salut'),
        const ChatMessage.user('Et ensuite ?'),
      ]);

      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['system'], 'Tu réponds en français.');
      final messages = body['messages'] as List<dynamic>;
      expect(messages.map((m) => (m as Map<String, dynamic>)['role']), <String>[
        'user',
        'assistant',
        'user',
      ]);
      expect(
        ((messages.first as Map<String, dynamic>)['content'] as List<dynamic>),
        <Object>[
          <String, String>{'type': 'text', 'text': 'Bonjour'},
        ],
      );
    });

    test('écarte les messages vides, qu’Anthropic refuse', () {
      // Le fil peut en porter : une réponse annoncée écourtée avant son
      // premier mot y laisse une bulle sans texte.
      final request = _request(<ChatMessage>[
        const ChatMessage.user('Bonjour'),
        const ChatMessage.assistant(''),
        const ChatMessage.user('Toujours là ?'),
      ]);

      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['messages'], hasLength(2));
    });

    test('joint les images au format attendu', () {
      final request = _request(<ChatMessage>[
        ChatMessage(
          role: ChatRole.user,
          content: 'Que vois-tu ?',
          images: <InlineImage>[
            InlineImage(
              mimeType: 'image/png',
              bytes: Uint8List.fromList(<int>[1, 2, 3]),
            ),
          ],
        ),
      ]);

      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final content =
          ((body['messages'] as List<dynamic>).single
                  as Map<String, dynamic>)['content']
              as List<dynamic>;
      final image = content.first as Map<String, dynamic>;
      expect(image['type'], 'image');
      final source = image['source'] as Map<String, dynamic>;
      expect(source['type'], 'base64');
      expect(source['media_type'], 'image/png');
      expect(source['data'], base64Encode(<int>[1, 2, 3]));
      // Le texte suit l'image : il la commente.
      expect((content.last as Map<String, dynamic>)['type'], 'text');
    });
  });

  group('le flux', () {
    test('ne garde que les fragments de texte', () async {
      final backend = _backend(<String>[
        'event: message_start',
        'data: {"type":"message_start","message":{"id":"msg"}}',
        'event: content_block_delta',
        'data: {"type":"content_block_delta","index":0,'
            '"delta":{"type":"text_delta","text":"Bon"}}',
        // Un bloc de réflexion n'est pas une réponse à afficher.
        'data: {"type":"content_block_delta","index":1,'
            '"delta":{"type":"thinking_delta","thinking":"hmm"}}',
        'data: {"type":"content_block_delta","index":0,'
            '"delta":{"type":"text_delta","text":"jour"}}',
        'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}',
        'data: {"type":"message_stop"}',
      ]);

      expect(
        await backend.generate(messages: <ChatMessage>[_question]).join(),
        'Bonjour',
      );
      expect(backend.incompleteReason, isNull);
    });

    test('un évènement error interrompt le flux avec son message', () async {
      final backend = _backend(<String>[
        'data: {"type":"content_block_delta","index":0,'
            '"delta":{"type":"text_delta","text":"Début"}}',
        'data: {"type":"error","error":{"type":"overloaded_error",'
            '"message":"Surcharge."}}',
      ]);

      final received = <String>[];
      await expectLater(
        backend
            .generate(messages: <ChatMessage>[_question])
            .forEach(received.add),
        throwsA(
          isA<PersonalApiStreamException>()
              .having((e) => e.message, 'message', 'Surcharge.')
              .having((e) => e.code, 'code', 'overloaded_error'),
        ),
      );
      // Le texte déjà reçu survit à l'échec.
      expect(received.join(), 'Début');
    });

    test('une réponse coupée par la limite est signalée', () async {
      final backend = _backend(<String>[
        'data: {"type":"content_block_delta","index":0,'
            '"delta":{"type":"text_delta","text":"Texte tronqué"}}',
        'data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"}}',
      ]);

      expect(
        await backend.generate(messages: <ChatMessage>[_question]).join(),
        'Texte tronqué',
      );
      expect(backend.incompleteReason, 'max_tokens');
    });

    test('un refus est signalé comme une réponse écourtée', () async {
      final backend = _backend(<String>[
        'data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}',
      ]);

      await backend.generate(messages: <ChatMessage>[_question]).drain<void>();
      expect(backend.incompleteReason, 'refusal');
    });

    test('une fin par séquence d’arrêt reste une fin normale', () async {
      final backend = _backend(<String>[
        'data: {"type":"content_block_delta","index":0,'
            '"delta":{"type":"text_delta","text":"Fini"}}',
        'data: {"type":"message_delta","delta":{"stop_reason":"stop_sequence"}}',
      ]);

      expect(
        await backend.generate(messages: <ChatMessage>[_question]).join(),
        'Fini',
      );
      expect(backend.incompleteReason, isNull);
    });
  });
}

// ---- utilitaires ----------------------------------------------------------

const _question = ChatMessage.user('Bonjour');

const _provider = ProviderConfig(
  id: 'anthropic',
  displayName: 'Anthropic',
  baseUrl: 'https://api.anthropic.com/v1',
  model: 'claude-example',
);

http.Request _request(List<ChatMessage> messages) {
  final backend = AnthropicBackend(
    provider: _provider,
    keyStore: _FakeApiKeyStore(),
  );
  addTearDown(backend.dispose);
  return backend.buildRequest(
    apiKey: 'secret',
    messages: messages,
    settings: const GenerationSettings(),
  );
}

AnthropicBackend _backend(List<String> script) {
  _ScriptedClient.script = script;
  final backend = AnthropicBackend(
    provider: _provider,
    keyStore: _FakeApiKeyStore(),
    clientFactory: _ScriptedClient.new,
  );
  addTearDown(backend.dispose);
  return backend;
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
