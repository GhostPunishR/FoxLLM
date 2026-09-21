// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:foxllm/l10n/app_localizations.dart';

/// Refus levés hors de tout widget, et donc écrits sans traductions.
///
/// Les moteurs, les fournisseurs et la bibliothèque de modèles lèvent des
/// exceptions bien avant qu'un écran soit en vue : ils n'ont ni `context` ni
/// langue. Leur message était donc écrit en français dans le code, et
/// s'affichait tel quel dans une interface anglaise.
///
/// Même principe que `LocalEngineFailure`, et même fragilité : la
/// reconnaissance se fait sur le texte d'origine. Le contrôle de dépôt qui
/// l'accompagne refuse qu'une de ces phrases change sans que sa traduction
/// suive.
enum BackendFailure {
  configureProvider('Configure le fournisseur, le modèle et la clé API.'),
  providerNoTextContent('Le fournisseur a répondu sans contenu texte.'),
  keyBeforeModels('Entre une clé API avant de récupérer les modèles.'),
  configureCustomBaseUrl('Configure la base URL du fournisseur personnalisé.'),
  invalidModelsResponse('Réponse de modèles invalide.'),
  missingModelsList('Liste de modèles absente de la réponse.'),
  noChatModels('Aucun modèle de chat disponible avec cette clé API.'),
  providerInterrupted('Le fournisseur a interrompu la réponse.'),
  providerReportedError('Le fournisseur a signalé une erreur.'),
  responseFailed('La réponse a échoué.'),
  notAGgufFile('Le fichier sélectionné doit être un modèle .gguf.'),
  emptyGgufFile('Le modèle GGUF sélectionné est vide.'),
  refuseDeleteOutside(
    'Refus de supprimer un fichier hors de la bibliothèque FoxLLM.',
  );

  const BackendFailure(this.message);

  /// Le message tel que le code le lève.
  final String message;

  /// Reconnaît un de ces refus, ou `null` si ce n'en est pas un.
  static BackendFailure? match(String message) {
    final trimmed = message.trim();
    for (final failure in BackendFailure.values) {
      if (failure.message == trimmed) {
        return failure;
      }
    }
    return null;
  }

  String describe(AppLocalizations l10n) => switch (this) {
    BackendFailure.configureProvider => l10n.backendConfigureProvider,
    BackendFailure.providerNoTextContent => l10n.backendProviderNoTextContent,
    BackendFailure.keyBeforeModels => l10n.backendKeyBeforeModels,
    BackendFailure.configureCustomBaseUrl => l10n.backendConfigureCustomBaseUrl,
    BackendFailure.invalidModelsResponse => l10n.backendInvalidModelsResponse,
    BackendFailure.missingModelsList => l10n.backendMissingModelsList,
    BackendFailure.noChatModels => l10n.backendNoChatModels,
    BackendFailure.providerInterrupted => l10n.backendProviderInterrupted,
    BackendFailure.providerReportedError => l10n.backendProviderReportedError,
    BackendFailure.responseFailed => l10n.backendResponseFailed,
    BackendFailure.notAGgufFile => l10n.backendNotAGgufFile,
    BackendFailure.emptyGgufFile => l10n.backendEmptyGgufFile,
    BackendFailure.refuseDeleteOutside => l10n.backendRefuseDeleteOutside,
  };
}

/// Nom du fournisseur d'un « aucune clé API configurée », ou `null`.
///
/// Ce refus-là porte un nom variable, donc il ne peut pas figurer dans
/// l'énumération ci-dessus, qui compare des phrases entières. Il est
/// pourtant le plus fréquent : c'est ce que voit quiconque active une API
/// personnelle sans avoir encore saisi sa clé.
String? missingApiKeyProvider(String message) {
  final match = RegExp(
    r'^Aucune clé API configurée pour (.+)\.$',
  ).firstMatch(message.trim());
  return match?.group(1);
}
