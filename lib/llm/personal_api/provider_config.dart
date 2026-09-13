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
