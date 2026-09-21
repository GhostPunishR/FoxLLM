// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:foxllm/core/theme/fox_theme.dart';
import 'package:foxllm/l10n/app_localizations.dart';

/// Ce qu'une déclinaison affiche d'elle-même.
///
/// Séparé de l'énumération à dessein : celle-ci décrit des couleurs et une
/// luminosité, qui ne changent pas d'une langue à l'autre, tandis que son nom
/// et sa description se traduisent.
extension FoxThemeLabels on FoxTheme {
  String label(AppLocalizations l10n) => switch (this) {
    FoxTheme.light => l10n.themeLightLabel,
    FoxTheme.dark => l10n.themeDarkLabel,
  };

  String description(AppLocalizations l10n) => switch (this) {
    FoxTheme.light => l10n.themeLightDescription,
    FoxTheme.dark => l10n.themeDarkDescription,
  };
}
