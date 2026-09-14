// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

enum ApiKeyPersistence { device, session }

class ProviderConfig {
  const ProviderConfig({
    required this.id,
    required this.displayName,
    required this.baseUrl,
    required this.model,
    this.apiKeyPersistence = ApiKeyPersistence.device,
  });

  final String id;
  final String displayName;
  final String baseUrl;
  final String model;
  final ApiKeyPersistence apiKeyPersistence;

  Uri get chatCompletionsUri =>
      Uri.parse('${normalizeBaseUrl(baseUrl)}/chat/completions');

  /// Point d'entrée de l'API Responses d'OpenAI.
  Uri get responsesUri => Uri.parse('${normalizeBaseUrl(baseUrl)}/responses');
}

/// Base URL sans espaces ni barre oblique finale, prête à être concaténée.
///
/// Toutes les barres finales sont retirées : une valeur collée depuis une
/// documentation (`https://api.example.com/v1//`) produisait sinon une URL à
/// double séparateur que certains fournisseurs rejettent.
String normalizeBaseUrl(String value) {
  var normalized = value.trim();
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

/// Serveur auquel une base URL confie la clé API : schéma, hôte et port
/// effectif, en minuscules.
///
/// C'est cette origine, et non la base URL entière, qui décide si une clé
/// enregistrée peut être réutilisée. Le chemin n'en fait pas partie : passer
/// de `/v1` à `/v1/` ou à `/openai/v1` reste le même serveur, alors que
/// changer d'hôte ou de port désigne un destinataire différent, à qui la clé
/// précédente ne doit jamais être envoyée.
///
/// Rend une chaîne vide quand la valeur n'est pas une URL absolue exploitable.
String personalApiOrigin(String baseUrl) {
  final uri = Uri.tryParse(normalizeBaseUrl(baseUrl));
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return '';
  }
  // `Uri.port` rend déjà le port par défaut du schéma quand il est absent :
  // `https://h` et `https://h:443` désignent donc bien la même origine.
  return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}:${uri.port}';
}
