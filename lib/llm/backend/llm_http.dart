// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:foxllm/core/storage/api_key_store.dart';
import 'package:foxllm/llm/backend/llm_backend.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm/llm/personal_api/provider_config.dart';

typedef HttpClientFactory = http.Client Function();

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
