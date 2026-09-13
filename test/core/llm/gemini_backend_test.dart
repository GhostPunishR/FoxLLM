// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/llm/chat_message.dart';
import 'package:foxllm/core/llm/gemini_backend.dart';
import 'package:foxllm/core/llm/provider_config.dart';
import 'package:foxllm/core/security/api_key_store.dart';
import 'package:http/http.dart' as http;

void main() {
  test('GeminiBackend streams text from Gemini SSE responses', () async {
    final backend = GeminiBackend(
      model: 'gemini-example',
      keyStore: _FakeApiKeyStore(),
      apiKeyPersistence: ApiKeyPersistence.session,
      clientFactory: () => _GeminiClient(),
    );

    final chunks = await backend
        .generate(
          messages: const <ChatMessage>[
            ChatMessage.system('Tu es FoxLLM.'),
            ChatMessage.user('Bonjour'),
          ],
        )
        .toList();

    expect(chunks.join(), 'Bonjour depuis Gemini');
    await backend.dispose();
  });
}

class _FakeApiKeyStore extends ApiKeyStore {
  @override
  Future<String?> read({
    required String providerId,
    required ApiKeyPersistence persistence,
  }) async {
    return 'secret';
  }
}

class _GeminiClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    expect(
      request.url.toString(),
      'https://generativelanguage.googleapis.com/v1beta/models/'
      'gemini-example:streamGenerateContent?alt=sse',
    );
    expect(request.headers['x-goog-api-key'], 'secret');

    final httpRequest = request as http.Request;
    final body = jsonDecode(httpRequest.body) as Map<String, dynamic>;
    expect(body['systemInstruction'], isNotNull);

    const payload =
        'data: {"candidates":[{"content":{"parts":[{"text":"Bonjour "}]}}]}\n\n'
        'data: {"candidates":[{"content":{"parts":[{"text":"depuis Gemini"}]}}]}\n\n';
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(payload)),
      200,
    );
  }
}
