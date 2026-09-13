// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'chat_message.dart';
import 'generation_settings.dart';
import 'llm_http.dart';
import 'personal_api_provider.dart';

class GeminiBackend extends HttpStreamingBackend {
  GeminiBackend({
    required this.model,
    required super.keyStore,
    required super.apiKeyPersistence,
    super.clientFactory,
  }) : super(keyProviderId: providerId);

  static const providerId = 'personal-api';

  final String model;

  @override
  String get id => 'gemini';

  @override
  String get displayName => 'Google Gemini';

  @override
  String get missingApiKeyMessage =>
      'Aucune clé API configurée pour Google Gemini.';

  Uri get _streamUri {
    final normalizedModel = model.startsWith('models/')
        ? model.substring('models/'.length)
        : model;
    return Uri.parse(
      '${geminiPersonalApiProvider.baseUrl}/models/'
      '${Uri.encodeComponent(normalizedModel)}:streamGenerateContent',
    ).replace(queryParameters: const <String, String>{'alt': 'sse'});
  }

  @override
  http.Request buildRequest({
    required String apiKey,
    required List<ChatMessage> messages,
    required GenerationSettings settings,
  }) {
    final systemText = messages
        .where((message) => message.role == ChatRole.system)
        .map((message) => message.content)
        .join('\n\n');
    final contents = messages
        .where((message) => message.role != ChatRole.system)
        .map(
          (message) => <String, Object>{
            'role': message.role == ChatRole.assistant ? 'model' : 'user',
            'parts': <Map<String, String>>[
              <String, String>{'text': message.content},
            ],
          },
        )
        .toList(growable: false);

    final body = <String, Object>{
      'contents': contents,
      'generationConfig': <String, Object>{
        'temperature': settings.temperature,
        'topP': settings.topP,
        'maxOutputTokens': settings.maxTokens,
      },
    };
    if (systemText.isNotEmpty) {
      body['systemInstruction'] = <String, Object>{
        'parts': <Map<String, String>>[
          <String, String>{'text': systemText},
        ],
      };
    }

    return http.Request('POST', _streamUri)
      ..headers.addAll(<String, String>{
        'x-goog-api-key': apiKey,
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = jsonEncode(body);
  }

  @override
  Iterable<String> extractDeltas(Map<String, dynamic> event) sync* {
    final candidates = event['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      return;
    }

    final candidate = candidates.first;
    if (candidate is! Map<String, dynamic>) {
      return;
    }

    final content = candidate['content'];
    if (content is! Map<String, dynamic>) {
      return;
    }

    final parts = content['parts'];
    if (parts is! List) {
      return;
    }

    for (final part in parts) {
      if (part is! Map<String, dynamic>) {
        continue;
      }
      final text = part['text'];
      if (text is String && text.isNotEmpty) {
        yield text;
      }
    }
  }
}
