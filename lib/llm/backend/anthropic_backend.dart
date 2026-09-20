// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:foxllm/llm/backend/llm_http.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/citation.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm/llm/personal_api/personal_api_provider.dart';
import 'package:foxllm/llm/personal_api/provider_config.dart';

export 'package:foxllm/llm/backend/llm_http.dart'
    show HttpClientFactory, PersonalApiHttpException;

/// Adaptateur de l'API Messages d'Anthropic.
///
/// Trois choses la séparent des API qui imitent `chat/completions` : la clé
/// voyage dans `x-api-key` et non dans `Authorization`, la version de l'API est
/// exigée sur chaque appel, et le flux est fait d'évènements nommés plutôt que
/// d'une suite de `choices`.
class AnthropicBackend extends HttpStreamingBackend {
  AnthropicBackend({
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
    // Les consignes système ne sont pas un message chez Anthropic : elles ont
    // leur propre champ, et en faire un message ferait échouer la requête.
    final systemText = messages
        .where((message) => message.role == ChatRole.system)
        .map((message) => message.content.trim())
        .where((content) => content.isNotEmpty)
        .join('\n\n');

    final turns = <Map<String, Object>>[
      for (final message in messages)
        if (message.role != ChatRole.system && !_isEmpty(message))
          <String, Object>{
            'role': message.role == ChatRole.assistant ? 'assistant' : 'user',
            'content': _content(message),
          },
    ];

    return http.Request('POST', provider.messagesUri)
      ..headers.addAll(<String, String>{
        'x-api-key': apiKey,
        'anthropic-version': anthropicApiVersion,
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = jsonEncode(<String, Object>{
        'model': provider.model,
        // Obligatoire chez Anthropic, contrairement aux autres fournisseurs.
        'max_tokens': settings.maxTokens,
        // Ni `temperature` ni `top_p` : les modèles récents d'Anthropic les
        // refusent avec une erreur 400, et les anciens s'en passent très bien.
        'stream': true,
        if (systemText.isNotEmpty) 'system': systemText,
        // L'outil de recherche d'Anthropic s'exécute chez lui : le modèle
        // décide seul d'y recourir, et rend ses sources dans le flux. Rien
        // n'est demandé au téléphone, qui ne consulte aucune page.
        if (settings.webSearch)
          'tools': <Map<String, Object>>[
            <String, Object>{
              'type': anthropicWebSearchTool,
              'name': 'web_search',
            },
          ],
        'messages': turns,
      });
  }

  @override
  Iterable<Citation> extractCitations(Map<String, dynamic> event) sync* {
    // Deux chemins, et les deux comptent. Le résultat de l'outil énumère les
    // pages consultées dès que la recherche aboutit ; les citations du texte
    // arrivent ensuite, au fil des phrases qu'elles appuient. Une réponse peut
    // citer moins de pages qu'elle n'en a lues, et l'utilisateur a intérêt à
    // voir les deux.
    final delta = event['delta'];
    if (delta is Map<String, dynamic> && delta['type'] == 'citations_delta') {
      final citation = delta['citation'];
      if (citation is Map<String, dynamic>) {
        final found = _citationOf(citation);
        if (found != null) {
          yield found;
        }
      }
    }

    final block = event['content_block'];
    if (block is! Map<String, dynamic> ||
        block['type'] != 'web_search_tool_result') {
      return;
    }
    final results = block['content'];
    if (results is! List) {
      return;
    }
    for (final result in results) {
      if (result is! Map<String, dynamic>) {
        continue;
      }
      final found = _citationOf(result);
      if (found != null) {
        yield found;
      }
    }
  }

  /// Rend la source décrite par [entry], ou `null` si elle n'a pas d'adresse.
  static Citation? _citationOf(Map<String, dynamic> entry) {
    final url = entry['url'];
    if (url is! String || url.trim().isEmpty) {
      return null;
    }
    final title = entry['title'];
    return Citation(
      url: url.trim(),
      title: title is String ? title.trim() : '',
    );
  }

  /// Vrai pour un message qui n'apporte rien : Anthropic refuse un contenu
  /// vide, et le fil peut en porter, par exemple une réponse annoncée écourtée
  /// avant son premier mot.
  static bool _isEmpty(ChatMessage message) =>
      message.content.trim().isEmpty && message.images.isEmpty;

  static List<Map<String, Object>> _content(ChatMessage message) =>
      <Map<String, Object>>[
        // Les images précèdent le texte : c'est l'ordre qu'Anthropic
        // recommande, le texte commentant alors ce qui a été montré.
        for (final image in message.images)
          <String, Object>{
            'type': 'image',
            'source': <String, String>{
              'type': 'base64',
              'media_type': image.mimeType,
              'data': image.base64Data,
            },
          },
        if (message.content.trim().isNotEmpty)
          <String, Object>{'type': 'text', 'text': message.content},
      ];

  @override
  Iterable<String> extractDeltas(Map<String, dynamic> event) sync* {
    if (event['type'] != 'content_block_delta') {
      return;
    }
    final delta = event['delta'];
    if (delta is! Map<String, dynamic>) {
      return;
    }
    // Seul le texte est repris : un bloc de réflexion ou un appel d'outil
    // n'est pas une réponse à afficher.
    if (delta['type'] != 'text_delta') {
      return;
    }
    final text = delta['text'];
    if (text is String && text.isNotEmpty) {
      yield text;
    }
  }

  @override
  PersonalApiStreamException? extractFailure(Map<String, dynamic> event) {
    if (event['type'] != 'error') {
      return null;
    }
    final error = event['error'];
    if (error is! Map<String, dynamic>) {
      return const PersonalApiStreamException(
        'Le fournisseur a interrompu la réponse.',
      );
    }
    final message = error['message'];
    final code = error['type'];
    return PersonalApiStreamException(
      message is String && message.trim().isNotEmpty
          ? message
          : 'Le fournisseur a interrompu la réponse.',
      code: code is String ? code : null,
    );
  }

  @override
  String? extractIncomplete(Map<String, dynamic> event) {
    if (event['type'] != 'message_delta') {
      return null;
    }
    final delta = event['delta'];
    if (delta is! Map<String, dynamic>) {
      return null;
    }
    final reason = delta['stop_reason'];
    // `end_turn` et `stop_sequence` sont des fins normales. Les deux autres
    // disent que la réponse s'arrête avant d'avoir tout dit.
    return switch (reason) {
      'max_tokens' => 'max_tokens',
      'refusal' => 'refusal',
      _ => null,
    };
  }
}
