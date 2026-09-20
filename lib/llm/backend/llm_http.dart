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

/// Le fournisseur n'a pas répondu, ou s'est tu au milieu de sa réponse.
///
/// Sans délai, une connexion acceptée puis abandonnée laisse l'application
/// attendre indéfiniment : le rond tourne, et rien ne dit que plus rien ne
/// viendra. Un réseau mobile perd des connexions sans prévenir, et le
/// fournisseur d'en face ne ferme pas toujours ce qu'il a ouvert.
class PersonalApiTimeoutException implements Exception {
  const PersonalApiTimeoutException(this.message);

  final String message;

  @override
  String toString() => message;
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
  /// Attente maximale de la réponse du fournisseur.
  ///
  /// Large : un prompt long se lit avant que le premier octet parte, et un
  /// fournisseur chargé met sa requête en file. Ce délai n'est pas là pour
  /// presser le fournisseur, mais pour que l'attente finisse un jour.
  ///
  /// Redéfinissable, pour que les tests n'aient pas à patienter une minute et
  /// demie afin de vérifier une seconde.
  Duration get responseTimeout => const Duration(seconds: 90);

  /// Attente maximale entre deux évènements du flux.
  ///
  /// Recompté à chaque évènement, ce n'est pas une limite de durée totale :
  /// une réponse peut prendre dix minutes tant qu'elle avance. C'est le
  /// silence qui est borné, pas la longueur.
  ///
  /// Généreux aussi : un modèle qui réfléchit avant d'écrire peut rester muet
  /// longtemps, et couper sa réflexion serait pire que d'attendre.
  Duration get idleTimeout => const Duration(minutes: 3);

  /// Attente maximale du corps d’une réponse en échec.
  ///
  /// Courte, et c’est volontaire : le code HTTP dit déjà que la requête a
  /// échoué, ce corps n’en donne que le détail. Le faire attendre aussi
  /// longtemps qu’une vraie réponse reviendrait à retenir l’utilisateur pour
  /// un échec déjà constaté.
  Duration get errorBodyTimeout => const Duration(seconds: 15);

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
  String? get incompleteReason => _latest?.incompleteReason;

  /// Sources relevées pendant la dernière génération, sans doublon et dans
  /// leur ordre d'apparition.
  ///
  /// Le contrat des moteurs ne transporte que du texte. Plutôt que d'y mêler
  /// un second type d'évènement, ce qui toucherait chaque moteur et chaque
  /// appelant, les citations sont relevées de côté et lues à la fin.
  List<Citation> get citations =>
      List<Citation>.unmodifiable(_latest?.citations ?? const <Citation>[]);

  /// Dernière génération lancée, celle que les deux lectures ci-dessus
  /// décrivent.
  ///
  /// Ces relevés appartiennent à une génération, pas au moteur. Rangés sur
  /// l'instance, ils étaient remis à zéro par la génération suivante : quand
  /// on quitte un fil pendant qu'il répond, l'ancienne génération s'arrête
  /// quelques instants après le départ de la nouvelle, et effaçait au passage
  /// les sources de celle qui venait de commencer.
  _HttpGeneration? _latest;

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
    _latest = generation;

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

        final response = await client
            .send(
              buildRequest(
                apiKey: apiKey,
                messages: messages,
                settings: settings,
              ),
            )
            .timeout(
              responseTimeout,
              onTimeout: () => throw PersonalApiTimeoutException(
                '$displayName n’a pas répondu dans les '
                '${responseTimeout.inSeconds} secondes.',
              ),
            );
        if (_shouldAbort(generation)) {
          return;
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          // Le délai ci-dessus s’arrête aux en-têtes. Un fournisseur qui
          // annonce son échec puis se tait en écrivant le corps laisserait
          // cette lecture attendre hors de tout délai : le rond tournerait
          // encore, pour une requête déjà perdue. Expirer ici ne coûte que
          // le détail de l’erreur, jamais son signalement.
          final body = await response.stream.bytesToString().timeout(
            errorBodyTimeout,
            onTimeout: () => '',
          );
          throw PersonalApiHttpException(
            statusCode: response.statusCode,
            body: body,
          );
        }

        // `timeout` sur un flux se recompte à chaque évènement : c'est bien
        // le silence qui déclenche, pas la durée de la réponse. L'erreur
        // ajoutée sort de la boucle ci-dessous, et le `finally` ferme le
        // client resté ouvert en face.
        //
        // Le chien de garde est posé après le tri des lignes, et non avant.
        // Un battement de cœur, le `: ping` d'OpenRouter ou le commentaire
        // qu'un proxy intercale pour tenir la connexion ouverte, est une ligne
        // comme une autre : relancer le compte à chaque battement laisserait
        // un fournisseur bloqué faire tourner le rond indéfiniment, ce que ce
        // délai existe précisément pour empêcher. Seule une charge utile
        // atteste d'un progrès, donc seule une charge utile le relance.
        final payloads = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .map(sseDataPayload)
            .where((payload) => payload != null)
            .cast<String>()
            .timeout(
              idleTimeout,
              onTimeout: (sink) => sink.addError(
                PersonalApiTimeoutException(
                  'La réponse de $displayName s’est interrompue : plus rien '
                  'depuis ${idleTimeout.inMinutes} minutes.',
                ),
              ),
            );

        await for (final payload in payloads) {
          if (_shouldAbort(generation)) {
            return;
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
            generation.incompleteReason = incomplete;
          }

          for (final citation in extractCitations(decoded)) {
            addCitation(generation.citations, citation);
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
  /// Sources relevées par cette génération, et par elle seule.
  final List<Citation> citations = <Citation>[];

  /// Raison pour laquelle cette génération s'est arrêtée avant la fin.
  String? incompleteReason;

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
