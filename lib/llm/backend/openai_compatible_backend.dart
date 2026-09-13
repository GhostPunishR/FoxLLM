// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm/llm/backend/llm_http.dart';
import 'package:foxllm/llm/personal_api/provider_config.dart';

export 'package:foxllm/llm/backend/llm_http.dart'
    show HttpClientFactory, PersonalApiHttpException;

class OpenAiCompatibleBackend extends HttpStreamingBackend {
  OpenAiCompatibleBackend({
    required this.provider,
    required super.keyStore,
    super.clientFactory,
  }) : super(
         keyProviderId: provider.id,
         apiKeyPersistence: provider.apiKeyPersistence,
       );

  final ProviderConfig provider;

  @override
  String get id => provider.id;

  @override
  String get displayName => provider.displayName;

  @override
  String get missingApiKeyMessage =>
      'Aucune clé API configurée pour ${provider.displayName}.';

  @override
  http.Request buildRequest({
    required String apiKey,
    required List<ChatMessage> messages,
    required GenerationSettings settings,
  }) {
    return http.Request('POST', provider.chatCompletionsUri)
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = jsonEncode(<String, Object>{
        'model': provider.model,
        'messages': messages.map((message) => message.toApiJson()).toList(),
        'temperature': settings.temperature,
        'top_p': settings.topP,
        'max_tokens': settings.maxTokens,
        'stream': true,
      });
  }

  @override
  Iterable<String> extractDeltas(Map<String, dynamic> event) sync* {
    final choices = event['choices'];
    if (choices is! List || choices.isEmpty) {
      return;
    }

    final firstChoice = choices.first;
    if (firstChoice is! Map<String, dynamic>) {
      return;
    }

    final delta = firstChoice['delta'];
    if (delta is! Map<String, dynamic>) {
      return;
    }

    final content = delta['content'];
    if (content is String && content.isNotEmpty) {
      yield content;
    }
  }
}
