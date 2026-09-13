// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:foxllm/llm/backend/llm_http.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm/llm/personal_api/personal_api_provider.dart';

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
            'parts': <Map<String, Object>>[
              if (message.content.isNotEmpty)
                <String, Object>{'text': message.content},
              // Gemini attend les images en ligne, encodées en base64, dans
              // les mêmes « parts » que le texte.
              for (final image in message.images)
                <String, Object>{
                  'inline_data': <String, String>{
                    'mime_type': image.mimeType,
                    'data': image.base64Data,
                  },
                },
            ],
          },
        )
        .toList(growable: false);

    final body = <String, Object>{
      'contents': contents,
      // Outil de recherche intégré de Gemini : le modèle interroge le web de
      // lui-même quand la question le demande.
      if (settings.webSearch)
        'tools': <Map<String, Object>>[
          <String, Object>{'google_search': <String, Object>{}},
        ],
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
