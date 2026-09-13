// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

class GenerationSettings {
  const GenerationSettings({
    this.temperature = 0.7,
    this.topP = 0.9,
    this.maxTokens = 512,
    this.webSearch = false,
  });

  final double temperature;
  final double topP;
  final int maxTokens;

  /// Autorise le modèle à consulter le web, quand son fournisseur le permet.
  ///
  /// Le moteur local et les API compatibles OpenAI l'ignorent : elles n'ont
  /// pas d'outil de recherche dans ce format de requête.
  final bool webSearch;
}
