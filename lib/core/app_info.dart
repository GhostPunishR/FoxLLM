// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

/// Ce que l'application dit d'elle-même : version, titulaire des droits et
/// adresse du code source. Trois constantes lues par « À propos », par
/// l'écran Licence et par les tests qui les tiennent en phase avec
/// `pubspec.yaml` et avec le site.
library;

/// Version de l'application, tenue en phase avec `pubspec.yaml` par un test.
const foxLlmVersion = '0.1.2';

/// Titulaire des droits, affiché dans « À propos » et porté par chaque fichier
/// source sous forme d'identifiant SPDX.
const foxLlmCopyright = 'Copyright © 2026 GhostPunishR';

/// Dépôt du code source.
///
/// L'AGPL demande que celui qui reçoit le programme puisse en obtenir le code :
/// l'application donne donc l'adresse plutôt que de laisser chercher.
const foxLlmSourceUrl = 'https://github.com/GhostPunishR/FoxLLM';
