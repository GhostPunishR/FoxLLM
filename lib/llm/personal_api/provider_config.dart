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

/// Destinataire auquel une base URL confie la clé API : schéma, hôte, port
/// effectif et chemin.
///
/// C'est ce destinataire, et non la base URL littérale, qui décide si une clé
/// enregistrée peut être réutilisée. Deux écritures d'une même adresse s'y
/// ramènent (barre finale, port par défaut explicite, casse de l'hôte), alors
/// que changer d'hôte, de port, de schéma ou de chemin désigne quelqu'un
/// d'autre, à qui la clé précédente ne doit jamais être envoyée.
///
/// Le chemin compte parce qu'une passerelle peut router chaque préfixe vers un
/// fournisseur différent : `/openai/v1` et `/anthropic/v1` sur le même hôte ne
/// partagent pas forcément les mêmes identifiants.
///
/// Rend une chaîne vide quand la valeur n'est pas une URL absolue exploitable.
String personalApiDestination(String baseUrl) {
  final uri = Uri.tryParse(normalizeBaseUrl(baseUrl));
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return '';
  }
  // `Uri.port` rend déjà le port par défaut du schéma quand il est absent :
  // `https://h` et `https://h:443` désignent donc le même destinataire. Le
  // chemin garde sa casse, contrairement à l'hôte : HTTP le distingue.
  return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}:${uri.port}'
      '${uri.path}';
}
