// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:foxllm/core/storage/api_key_store.dart';
import 'package:foxllm/llm/backend/llm_backend.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/citation.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm/llm/personal_api/provider_config.dart';

typedef HttpClientFactory = http.Client Function();

/// Échec annoncé dans le flux d'une réponse pourtant acceptée.
///
/// Un HTTP 200 n'engage que l'ouverture du flux : le fournisseur peut ensuite
/// y annoncer un échec. Sans ce type, un filtrage qui ne garde que le texte
/// faisait passer cet échec pour une fin normale, et la réponse partielle
/// pour une réponse complète.
class PersonalApiStreamException implements Exception {
  const PersonalApiStreamException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => code == null ? message : '$message ($code)';
}

/// Erreur renvoyée par un fournisseur distant sur une réponse non 2xx.
class PersonalApiHttpException implements Exception {
  const PersonalApiHttpException({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;

  @override
  String toString() => 'HTTP $statusCode: $body';
}

/// Socle commun aux backends distants qui streament une réponse en SSE.
///
/// Les sous-classes ne décrivent que ce qui est propre au fournisseur : la
/// requête à envoyer et la façon de lire les fragments de texte d'un évènement.
/// L'annulation, la fermeture du client HTTP et le cycle de vie
/// `stop()`/`dispose()` sont mutualisés ici, car ce sont eux qui portaient
/// jusque-là toute la duplication entre fournisseurs.
abstract class HttpStreamingBackend implements LlmBackend {
  HttpStreamingBackend({
    required this.keyStore,
    required this.keyProviderId,
    required this.apiKeyPersistence,
    HttpClientFactory? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final ApiKeyStore keyStore;

  /// Identifiant sous lequel la clé API est rangée dans [ApiKeyStore].
  final String keyProviderId;
  final ApiKeyPersistence apiKeyPersistence;

  final HttpClientFactory _clientFactory;
  final Set<_HttpGeneration> _activeGenerations = <_HttpGeneration>{};
  bool _disposed = false;

  /// Requête complète à envoyer, clé API déjà résolue.
  http.Request buildRequest({
    required String apiKey,
    required List<ChatMessage> messages,
    required GenerationSettings settings,
  });

  /// Fragments de texte portés par un évènement SSE décodé.
  Iterable<String> extractDeltas(Map<String, dynamic> event);

  /// Sources citées par un évènement SSE décodé.
  ///
  /// Vide par défaut : seuls les fournisseurs dotés d'un outil de recherche
  /// en produisent, et leur format diffère autant que celui du texte.
  Iterable<Citation> extractCitations(Map<String, dynamic> event) =>
      const <Citation>[];

  /// Échec annoncé par un évènement SSE décodé, ou `null`.
  ///
  /// `null` par défaut : tous les fournisseurs n'annoncent pas leurs échecs
  /// dans le flux.
  PersonalApiStreamException? extractFailure(Map<String, dynamic> event) =>
      null;

  /// Raison d'une réponse écourtée, ou `null` si elle est allée au bout.
  ///
  /// Ce n'est pas un échec : le texte reçu est bon, il est seulement
  /// incomplet. La distinction évite de jeter ce texte comme une erreur, et
  /// de le présenter comme une réponse entière.
  String? extractIncomplete(Map<String, dynamic> event) => null;

  /// Raison pour laquelle la dernière réponse s'est arrêtée avant la fin.
  String? get incompleteReason => _incompleteReason;

  String? _incompleteReason;

  /// Sources relevées pendant la dernière génération, sans doublon et dans
  /// leur ordre d'apparition.
  ///
  /// Le contrat des moteurs ne transporte que du texte. Plutôt que d'y mêler
  /// un second type d'évènement, ce qui toucherait chaque moteur et chaque
  /// appelant, les citations sont relevées de côté et lues à la fin.
  List<Citation> get citations => List<Citation>.unmodifiable(_citations);

  final List<Citation> _citations = <Citation>[];

  /// Message d'erreur quand aucune clé API n'est configurée.
  String get missingApiKeyMessage =>
      'Aucune clé API configurée pour $displayName.';

  @override
  Stream<String> generate({
    required List<ChatMessage> messages,
    GenerationSettings settings = const GenerationSettings(),
  }) async* {
    if (_disposed) {
      throw StateError('Le backend $displayName a déjà été libéré.');
    }

    final generation = _HttpGeneration();
    _activeGenerations.add(generation);
    // Les sources appartiennent à la réponse en cours, pas à la précédente.
    _citations.clear();
    _incompleteReason = null;

    try {
      try {
        final apiKey = await keyStore.read(
          providerId: keyProviderId,
          persistence: apiKeyPersistence,
        );
        if (_shouldAbort(generation)) {
          return;
        }
        if (apiKey == null || apiKey.trim().isEmpty) {
          throw StateError(missingApiKeyMessage);
        }

        final client = _clientFactory();
        generation.attachClient(client);
        if (_shouldAbort(generation)) {
          return;
        }

        final response = await client.send(
          buildRequest(apiKey: apiKey, messages: messages, settings: settings),
        );
        if (_shouldAbort(generation)) {
          return;
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw PersonalApiHttpException(
            statusCode: response.statusCode,
            body: await response.stream.bytesToString(),
          );
        }

        final lines = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter());

        await for (final line in lines) {
          if (_shouldAbort(generation)) {
            return;
          }

          final payload = sseDataPayload(line);
          if (payload == null) {
            continue;
          }
          if (payload == _sseDoneMarker) {
            break;
          }

          final decoded = jsonDecode(payload);
          if (decoded is! Map<String, dynamic>) {
            continue;
          }

          // L'échec est regardé avant le texte : un évènement qui annonce
          // l'abandon de la réponse ne doit pas être lu comme une fin propre.
          final failure = extractFailure(decoded);
          if (failure != null) {
            throw failure;
          }
          final incomplete = extractIncomplete(decoded);
          if (incomplete != null) {
            _incompleteReason = incomplete;
          }

          for (final citation in extractCitations(decoded)) {
            addCitation(_citations, citation);
          }
          yield* Stream<String>.fromIterable(extractDeltas(decoded));
        }
      } catch (_) {
        if (_shouldAbort(generation)) {
          return;
        }
        rethrow;
      }
    } finally {
      generation.cancel();
      _activeGenerations.remove(generation);
    }
  }

  bool _shouldAbort(_HttpGeneration generation) =>
      _disposed || generation.isCancelled;

  @override
  Future<void> stop() async {
    for (final generation in List<_HttpGeneration>.of(_activeGenerations)) {
      generation.cancel();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await stop();
  }
}

const _sseDoneMarker = '[DONE]';

/// Charge utile d'une ligne SSE `data:`, ou `null` si la ligne n'en porte pas.
///
/// Les commentaires (`:`), les champs `event:`/`id:` et les lignes vides de
/// séparation d'évènements sont ignorés.
String? sseDataPayload(String line) {
  if (!line.startsWith('data:')) {
    return null;
  }
  final payload = line.substring('data:'.length).trim();
  return payload.isEmpty ? null : payload;
}

class _HttpGeneration {
  http.Client? _client;
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void attachClient(http.Client client) {
    _client = client;
    if (_isCancelled) {
      client.close();
      _client = null;
    }
  }

  void cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    _client?.close();
    _client = null;
  }
}
