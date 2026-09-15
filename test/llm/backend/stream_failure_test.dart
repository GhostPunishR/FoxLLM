// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/storage/api_key_store.dart';
import 'package:foxllm/llm/backend/llm_http.dart';
import 'package:foxllm/llm/backend/openai_responses_backend.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/personal_api/provider_config.dart';
import 'package:http/http.dart' as http;

const _provider = ProviderConfig(
  id: 'openai',
  displayName: 'OpenAI',
  baseUrl: 'https://api.openai.com/v1',
  model: 'gpt-5',
);

void main() {
  group('un HTTP 200 n’est pas une réussite', () {
    // Écrit sans les types ajoutés par le correctif, pour pouvoir être
    // exécuté tel quel sur la version auditée, où il échoue : le flux s'y
    // terminait normalement, en rendant une réponse vide.
    test('un échec annoncé ne se termine pas comme une réponse vide', () async {
      final backend = _backend(<String>[
        'data: {"type":"response.failed","response":{"error":'
            '{"code":"server_error","message":"Le modèle a échoué."}}}',
        'data: [DONE]',
      ]);

      await expectLater(
        backend.generate(messages: <ChatMessage>[_question]).join(),
        throwsA(anything),
      );
    });

    test('response.failed interrompt le flux avec son message', () async {
      final backend = _backend(<String>[
        'data: {"type":"response.created"}',
        'data: {"type":"response.failed","response":{"error":'
            '{"code":"server_error","message":"Le modèle a échoué."}}}',
        'data: [DONE]',
      ]);

      // Le défaut d'origine : le filtrage ne gardant que le texte laissait
      // passer cet évènement, et le flux se terminait comme une réponse vide
      // mais réussie.
      await expectLater(
        backend.generate(messages: <ChatMessage>[_question]).toList(),
        throwsA(
          isA<PersonalApiStreamException>()
              .having((e) => e.message, 'message', 'Le modèle a échoué.')
              .having((e) => e.code, 'code', 'server_error'),
        ),
      );
    });

    test('quelques fragments puis une erreur : le texte reçu survit', () async {
      final backend = _backend(<String>[
        'data: {"type":"response.output_text.delta","delta":"Début de "}',
        'data: {"type":"response.output_text.delta","delta":"réponse"}',
        'data: {"type":"error","code":"rate_limit_exceeded",'
            '"message":"Trop de requêtes."}',
        'data: [DONE]',
      ]);

      final received = <String>[];
      await expectLater(
        backend
            .generate(messages: <ChatMessage>[_question])
            .forEach(received.add),
        throwsA(isA<PersonalApiStreamException>()),
      );
      expect(received.join(), 'Début de réponse');
    });

    test('l’évènement error nu porte son message', () async {
      final backend = _backend(<String>[
        'data: {"type":"error","message":"Clé invalide.","code":"invalid_key"}',
      ]);

      await expectLater(
        backend.generate(messages: <ChatMessage>[_question]).toList(),
        throwsA(
          isA<PersonalApiStreamException>().having(
            (e) => e.toString(),
            'toString',
            contains('Clé invalide.'),
          ),
        ),
      );
    });
  });

  group('une réponse écourtée n’est pas une erreur', () {
    test('le texte est gardé, et la raison relevée', () async {
      final backend = _backend(<String>[
        'data: {"type":"response.output_text.delta","delta":"Texte tronqué"}',
        'data: {"type":"response.incomplete","response":'
            '{"incomplete_details":{"reason":"max_output_tokens"}}}',
        'data: [DONE]',
      ]);

      expect(
        await backend.generate(messages: <ChatMessage>[_question]).join(),
        'Texte tronqué',
      );
      expect(backend.incompleteReason, 'max_output_tokens');
    });
  });

  group('une réponse normale reste normale', () {
    test('response.completed ne signale ni échec ni troncature', () async {
      final backend = _backend(<String>[
        'data: {"type":"response.output_text.delta","delta":"Bonjour"}',
        'data: {"type":"response.completed"}',
        'data: [DONE]',
      ]);

      expect(
        await backend.generate(messages: <ChatMessage>[_question]).join(),
        'Bonjour',
      );
      expect(backend.incompleteReason, isNull);
    });

    test(
      'la raison d’une réponse écourtée ne survit pas à la suivante',
      () async {
        final backend = _backend(<String>[
          'data: {"type":"response.incomplete","response":'
              '{"incomplete_details":{"reason":"max_output_tokens"}}}',
          'data: [DONE]',
        ]);
        await backend
            .generate(messages: <ChatMessage>[_question])
            .drain<void>();
        expect(backend.incompleteReason, 'max_output_tokens');

        // Une seconde génération repart d'un état propre.
        _ScriptedClient.script = <String>[
          'data: {"type":"response.output_text.delta","delta":"Suite"}',
          'data: [DONE]',
        ];
        expect(
          await backend.generate(messages: <ChatMessage>[_question]).join(),
          'Suite',
        );
        expect(backend.incompleteReason, isNull);
      },
    );
  });

  group('une annulation volontaire ne devient pas une erreur', () {
    test('arrêter en cours de route termine le flux sans lever', () async {
      final backend = _backend(<String>[
        'data: {"type":"response.output_text.delta","delta":"Début"}',
        'data: {"type":"response.output_text.delta","delta":" puis"}',
        'data: [DONE]',
      ]);

      final received = <String>[];
      final done = Completer<void>();
      backend
          .generate(messages: <ChatMessage>[_question])
          .listen(
            received.add,
            onError: (Object error) => done.completeError(error),
            onDone: done.complete,
          );

      await backend.stop();
      // Aucune erreur : une interruption demandée n'a rien d'un échec.
      await expectLater(done.future, completes);
    });
  });
}

const _question = ChatMessage.user('Bonjour');

OpenAiResponsesBackend _backend(List<String> script) {
  _ScriptedClient.script = script;
  final backend = OpenAiResponsesBackend(
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
