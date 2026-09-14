// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:foxllm/llm/backend/llm_http.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/citation.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm/llm/personal_api/provider_config.dart';

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
  Iterable<Citation> extractCitations(Map<String, dynamic> event) sync* {
    // Les citations arrivent au fil du texte, dans leur propre évènement.
    if (event['type'] != 'response.output_text.annotation.added') {
      return;
    }
    final citation = _citationFrom(event['annotation']);
    if (citation != null) {
      yield citation;
    }
  }

  /// Lit une annotation `url_citation`.
  ///
  /// L'API Responses pose l'adresse et le titre à plat sur l'annotation, là
  /// où `chat/completions` les range sous une clé `url_citation`. Les deux
  /// formes sont acceptées : plusieurs fournisseurs compatibles imitent la
  /// seconde.
  static Citation? _citationFrom(Object? annotation) {
    if (annotation is! Map<Object?, Object?>) {
      return null;
    }
    if (annotation['type'] != 'url_citation') {
      return null;
    }
    final nested = annotation['url_citation'];
    final source = nested is Map<Object?, Object?> ? nested : annotation;
    final url = source['url'];
    if (url is! String || url.trim().isEmpty) {
      return null;
    }
    final title = source['title'];
    return Citation(url: url.trim(), title: title is String ? title : '');
  }

  /// Échecs annoncés dans un flux pourtant ouvert en HTTP 200.
  ///
  /// Deux formes, décrites par le SDK officiel : `error`, qui porte le message
  /// à plat, et `response.failed`, qui range l'erreur sous la réponse
  /// abandonnée. Sans ce traitement, le filtrage ne gardant que le texte
  /// faisait passer les deux pour une fin normale.
  @override
  PersonalApiStreamException? extractFailure(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'error':
        return PersonalApiStreamException(
          _text(event['message']) ?? 'Le fournisseur a signalé une erreur.',
          code: _text(event['code']),
        );
      case 'response.failed':
        final response = event['response'];
        final error = response is Map<Object?, Object?>
            ? response['error']
            : null;
        final details = error is Map<Object?, Object?> ? error : null;
        return PersonalApiStreamException(
          _text(details?['message']) ?? 'La réponse a échoué.',
          code: _text(details?['code']),
        );
      default:
        return null;
    }
  }

  /// Réponse arrêtée avant sa fin, avec la raison donnée par le fournisseur.
  ///
  /// Le texte reçu reste bon : ce n'est pas une erreur, mais la réponse n'est
  /// pas entière pour autant.
  @override
  String? extractIncomplete(Map<String, dynamic> event) {
    if (event['type'] != 'response.incomplete') {
      return null;
    }
    final response = event['response'];
    final details = response is Map<Object?, Object?>
        ? response['incomplete_details']
        : null;
    final reason = details is Map<Object?, Object?> ? details['reason'] : null;
    return _text(reason) ?? 'raison non précisée';
  }

  /// Une chaîne non vide, ou `null`.
  static String? _text(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
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
