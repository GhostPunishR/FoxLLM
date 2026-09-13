import 'package:flutter/material.dart';

import 'fox_palette.dart';

/// Déclinaisons disponibles dans Paramètres → Apparence.
enum FoxTheme {
  dark('Sombre renard', 'Noir chaud et orange'),
  light('Clair renard', 'Blanc crème et orange');

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

  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: fox.accent,
        brightness: theme.brightness,
      ).copyWith(
        primary: fox.accent,
        onPrimary: fox.onAccent,
        surface: fox.surfaceRaised,
        onSurface: fox.textPrimary,
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
