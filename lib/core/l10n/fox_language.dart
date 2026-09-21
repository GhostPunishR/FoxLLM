// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/widgets.dart';

/// Langue de l'interface.
///
/// [system] n'est pas une langue mais une absence de choix : `MaterialApp`
/// reçoit alors `null` et résout lui-même la langue de l'appareil, en se
/// rabattant sur le français si elle n'est pas servie. C'est le défaut, pour
/// qu'une installation sur un téléphone anglophone parle anglais sans que
/// personne n'ait rien à régler.
enum FoxLanguage {
  system(null),
  french(Locale('fr')),
  english(Locale('en'));

  const FoxLanguage(this.locale);

  /// Langue à imposer, ou `null` pour suivre l'appareil.
  final Locale? locale;
}
