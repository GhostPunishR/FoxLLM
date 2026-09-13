// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';

import 'fox_palette.dart';

/// Déclinaisons disponibles dans Paramètres → Apparence.
///
/// L'ordre est celui de l'écran Apparence : la déclinaison claire d'abord,
/// puisque c'est celle appliquée par défaut.
enum FoxTheme {
  light('Clair renard', 'Blanc crème et orange'),
  dark('Sombre renard', 'Noir chaud et orange');

  const FoxTheme(this.label, this.description);

  final String label;
  final String description;

  FoxPalette get palette => switch (this) {
    FoxTheme.dark => FoxPalette.dark,
    FoxTheme.light => FoxPalette.light,
  };

  Brightness get brightness => switch (this) {
    FoxTheme.dark => Brightness.dark,
    FoxTheme.light => Brightness.light,
  };

  ThemeData get themeData => _buildTheme(this);
}

ThemeData _buildTheme(FoxTheme theme) {
  final fox = theme.palette;
  final isDark = theme.brightness == Brightness.dark;

  // Tous les rôles de surface et de contour sont repris de la palette : les
  // widgets Material (Card, ListTile, champs) s'appuient dessus, et laisser
  // ceux générés automatiquement donnait des écrans aux teintes étrangères au
  // thème choisi.
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: fox.accent,
        brightness: theme.brightness,
      ).copyWith(
        primary: fox.accent,
        onPrimary: fox.onAccent,
        primaryContainer: fox.accentSurface,
        onPrimaryContainer: fox.accentText,
        secondary: fox.accent,
        onSecondary: fox.onAccent,
        secondaryContainer: fox.accentSurface,
        onSecondaryContainer: fox.accentText,
        surface: fox.background,
        onSurface: fox.textPrimary,
        onSurfaceVariant: fox.textSecondary,
        surfaceContainerLowest: fox.background,
        surfaceContainerLow: fox.surfaceRaised,
        surfaceContainer: fox.surfaceRaised,
        surfaceContainerHigh: fox.surfaceInput,
        surfaceContainerHighest: fox.surfaceInput,
        surfaceTint: Colors.transparent,
        outline: fox.borderStrong,
        outlineVariant: fox.border,
        inverseSurface: fox.textPrimary,
        onInverseSurface: fox.background,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: theme.brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: fox.background,
    canvasColor: fox.background,
    dividerColor: fox.border,
    extensions: <ThemeExtension<dynamic>>[fox],
    appBarTheme: AppBarTheme(
      backgroundColor: fox.background,
      foregroundColor: fox.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: fox.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: fox.border),
      ),
    ),
    listTileTheme: ListTileThemeData(
      textColor: fox.textPrimary,
      iconColor: fox.textPrimary,
      subtitleTextStyle: TextStyle(color: fox.textSecondary, fontSize: 13),
    ),
    textTheme: ThemeData(brightness: theme.brightness).textTheme.apply(
      bodyColor: fox.textPrimary,
      displayColor: fox.textPrimary,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: fox.accentSurface,
      side: BorderSide(color: fox.accentBorder),
      labelStyle: TextStyle(color: fox.accentText),
      iconTheme: IconThemeData(color: fox.accentText),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: fox.surfaceRaised,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: fox.surfaceRaised,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: fox.accent),
    // Le clavier suit la luminosité du thème, sinon il reste sombre sur clair.
    textSelectionTheme: TextSelectionThemeData(cursorColor: fox.accent),
    iconTheme: IconThemeData(color: fox.textPrimary),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll<Color>(
        isDark ? fox.borderStrong : fox.border,
      ),
    ),
  );
}
