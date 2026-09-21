// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:foxllm/core/diagnostics/first_error.dart';
import 'package:foxllm/core/l10n/language_provider.dart';
import 'package:foxllm/core/theme/theme_provider.dart';
import 'package:foxllm/features/chat/chat_backend_host.dart';
import 'package:foxllm/l10n/app_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Avant tout le reste : une erreur au démarrage doit pouvoir se lire sur
  // l'appareil, et non seulement dans un journal branché à un ordinateur.
  installFirstErrorScreen();
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
  runApp(const ProviderScope(child: FoxLlmApp()));
}

class FoxLlmApp extends ConsumerWidget {
  const FoxLlmApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(foxThemeProvider);
    final language = ref.watch(foxLanguageProvider);
    final palette = theme.palette;
    final isDark = theme.brightness == Brightness.dark;

    // Les barres système suivent le thème, sinon leurs icônes deviennent
    // illisibles sur la déclinaison claire.
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: palette.background,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarDividerColor: palette.background,
      ),
    );

    return MaterialApp(
      title: 'FoxLLM',
      debugShowCheckedModeBanner: false,
      theme: theme.themeData,
      // Sans ces délégations, Flutter ne dispose que de ses textes anglais :
      // le menu d'un champ de saisie proposait « Cut », « Copy » et « Paste »
      // au milieu d'une application entièrement française. Ils suivent
      // désormais la langue, comme le reste.
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      // `null` laisse Flutter résoudre la langue de l'appareil, et se rabattre
      // sur la première langue servie, le français, si elle n'en est pas.
      locale: language.locale,
      home: const ChatBackendHost(),
    );
  }
}
