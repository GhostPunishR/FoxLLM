// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

/// Plafond de jetons d'une réponse ordinaire.
///
/// 512 était trop court : une réponse qui contient du code le dépasse presque
/// toujours, et elle s'arrêtait alors au milieu d'une ligne. Ce plafond vaut
/// environ deux cents lignes.
///
/// Il n'est pas retiré pour autant. Le moteur local réserve son cache pour la
/// question plus le plafond : sans limite, un modèle à large fenêtre
/// demanderait d'emblée de quoi la remplir, ce qu'un téléphone n'a pas. La
/// fenêtre du modèle le borne de toute façon, et un plafond atteint est
/// désormais annoncé plutôt que subi.
const int defaultMaxTokens = 2048;

class GenerationSettings {
  const GenerationSettings({
    this.temperature = 0.7,
    this.topP = 0.9,
    this.maxTokens = defaultMaxTokens,
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
