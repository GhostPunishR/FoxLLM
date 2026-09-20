// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:foxllm/l10n/app_localizations.dart';

/// Monte un écran comme l'application le monte, traductions comprises.
///
/// Un `MaterialApp` nu ne porte aucune délégation : tout appel à
/// `AppLocalizations.of(context)` y échoue. Les bancs qui construisaient leur
/// `MaterialApp` à la main passaient donc à côté de la moitié de ce que
/// l'écran fait réellement.
///
/// Le français est imposé plutôt que laissé au système : c'est la langue
/// source, celle dans laquelle les textes sont écrits, donc celle sur laquelle
/// les affirmations portent. Un banc qui suivrait la langue de la machine
/// d'intégration continue échouerait ailleurs qu'ici.
MaterialApp localizedApp({
  required Widget home,
  ThemeData? theme,
  Locale locale = const Locale('fr'),
  TransitionBuilder? builder,
  GlobalKey<NavigatorState>? navigatorKey,
}) => MaterialApp(
  navigatorKey: navigatorKey,
  theme: theme,
  locale: locale,
  builder: builder,
  localizationsDelegates: const <LocalizationsDelegate<Object>>[
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);
