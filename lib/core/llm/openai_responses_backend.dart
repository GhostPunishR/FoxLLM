// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'chat_message.dart';
import 'generation_settings.dart';
import 'llm_http.dart';
import 'provider_config.dart';

/// Backend OpenAI parlant l'API Responses.
///
/// `chat/completions` reste le format que les autres fournisseurs imitent,
/// mais il n'expose aucun outil intégré : la recherche web d'OpenAI ne vit que
/// dans `responses`. Le format diffère sur trois points : les messages
/// deviennent des éléments d'`input`, la consigne système passe par
/// `instructions`, et la réponse arrive en évènements typés plutôt qu'en
/// fragments de complétion.
class OpenAiResponsesBackend extends HttpStreamingBackend {
  OpenAiResponsesBackend({
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
    // La consigne système a son champ dédié : la laisser dans `input` la
    // placerait au même rang qu'un tour de conversation.
    final instructions = messages
        .where((message) => message.role == ChatRole.system)
        .map((message) => message.content)
        .join('\n\n');

    final input = messages
        .where((message) => message.role != ChatRole.system)
        .map(_inputItem)
        .toList(growable: false);

    return http.Request('POST', provider.responsesUri)
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = jsonEncode(<String, Object>{
        'model': provider.model,
        'input': input,
        if (instructions.isNotEmpty) 'instructions': instructions,
        'temperature': settings.temperature,
        'top_p': settings.topP,
        'max_output_tokens': settings.maxTokens,
        if (settings.webSearch)
          'tools': <Map<String, Object>>[
            <String, Object>{'type': 'web_search'},
          ],
        'stream': true,
      });
  }

  /// Un tour de conversation, en morceaux quand il porte des images.
  Map<String, Object> _inputItem(ChatMessage message) {
    final role = message.role == ChatRole.assistant ? 'assistant' : 'user';
    if (message.images.isEmpty) {
      return <String, Object>{'role': role, 'content': message.content};
    }
    return <String, Object>{
      'role': role,
      'content': <Map<String, Object>>[
        if (message.content.isNotEmpty)
          <String, Object>{'type': 'input_text', 'text': message.content},
        for (final image in message.images)
          <String, Object>{'type': 'input_image', 'image_url': image.dataUrl},
      ],
    };
  }

  @override
  Iterable<String> extractDeltas(Map<String, dynamic> event) sync* {
    // Le flux porte une douzaine de types d'évènements : création, appels
    // d'outils, fin de réponse. Seuls les fragments de texte nous intéressent.
    if (event['type'] != 'response.output_text.delta') {
      return;
    }
    final delta = event['delta'];
    if (delta is String && delta.isNotEmpty) {
      yield delta;
    }
  }
}
