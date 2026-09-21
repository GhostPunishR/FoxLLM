// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:foxllm/core/l10n/fox_language.dart';
import 'package:foxllm/l10n/app_localizations.dart';

/// Ce qu'une langue affiche d'elle-même.
extension FoxLanguageLabels on FoxLanguage {
  /// Le nom d'une langue s'écrit dans cette langue, jamais traduit.
  ///
  /// Un anglophone égaré dans une interface française doit pouvoir retrouver
  /// « English » sans comprendre un mot de ce qui l'entoure, et inversement.
  /// Traduire ces deux noms rendrait le réglage inutilisable à ceux qui en ont
  /// le plus besoin.
  String label(AppLocalizations l10n) => switch (this) {
    FoxLanguage.system => l10n.languageSystemLabel,
    FoxLanguage.french => 'Français',
    FoxLanguage.english => 'English',
  };

  String description(AppLocalizations l10n) => switch (this) {
    FoxLanguage.system => l10n.languageSystemDescription,
    FoxLanguage.french => l10n.languageFrenchDescription,
    FoxLanguage.english => l10n.languageEnglishDescription,
  };
}
