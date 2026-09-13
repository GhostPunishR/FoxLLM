// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// Rôles de couleur de FoxGPT, injectés dans le `ThemeData`.
///
/// Les écrans ne codent plus de valeur en dur : ils lisent ces rôles, ce qui
/// permet de basculer entre les déclinaisons claire et sombre sans toucher aux
/// widgets. Les deux palettes sont teintées de l'orange du renard plutôt que
/// des gris neutres d'un thème Material par défaut.
@immutable
class FoxPalette extends ThemeExtension<FoxPalette> {
  const FoxPalette({
    required this.background,
    required this.surfaceRaised,
    required this.surfaceInput,
    required this.surfaceSelected,
    required this.userBubble,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.onAccent,
    required this.accentText,
    required this.accentSurface,
    required this.accentBorder,
    required this.codeComment,
    required this.codeKeyword,
    required this.codeString,
    required this.codeNumber,
    required this.codeCall,
  });

  /// Fond général des écrans.
  final Color background;

  /// Cartes et panneaux posés sur le fond.
  final Color surfaceRaised;

  /// Champs de saisie et composer.
  final Color surfaceInput;

  /// Élément sélectionné dans une liste.
  final Color surfaceSelected;

  /// Bulle d'un message envoyé par l'utilisateur.
  final Color userBubble;

  final Color border;
  final Color borderStrong;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// Orange FoxGPT, pour les aplats et actions principales.
  final Color accent;

  /// Contenu posé sur [accent].
  final Color onAccent;

  /// Orange lisible en texte ou en icône sur [accentSurface].
  final Color accentText;

  final Color accentSurface;
  final Color accentBorder;

  /// Coloration syntaxique des blocs de code du chat.
  ///
  /// Le texte courant du code reprend [textPrimary] ; ces rôles ne portent que
  /// ce qui s'en détache. Chacun garde un contraste d'au moins 4,5:1 sur
  /// [surfaceInput], le fond des blocs.
  final Color codeComment;
  final Color codeKeyword;
  final Color codeString;
  final Color codeNumber;

  /// Nom d'une fonction appelée ou déclarée.
  final Color codeCall;

  static const dark = FoxPalette(
    background: Color(0xFF0F0B08),
    surfaceRaised: Color(0xFF1A1310),
    surfaceInput: Color(0xFF241A15),
    surfaceSelected: Color(0xFF2A1E17),
    userBubble: Color(0xFF2E2018),
    border: Color(0xFF2E231C),
    borderStrong: Color(0xFF45332A),
    textPrimary: Color(0xFFF7EFE9),
    textSecondary: Color(0xFFB9A79B),
    textTertiary: Color(0xFF8E7C71),
    accent: Color(0xFFFC6117),
    onAccent: Color(0xFF1A0E07),
    accentText: Color(0xFFFF8A4C),
    accentSurface: Color(0xFF33200F),
    accentBorder: Color(0xFF5E3A1C),
    codeComment: Color(0xFF9A8778),
    codeKeyword: Color(0xFFFF8A4C),
    codeString: Color(0xFFA5C97A),
    codeNumber: Color(0xFFE0A85C),
    codeCall: Color(0xFF7FBEEA),
  );

  static const light = FoxPalette(
    background: Color(0xFFFFF9F4),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceInput: Color(0xFFFDF1E7),
    surfaceSelected: Color(0xFFFBE4D3),
    userBubble: Color(0xFFFFE6D2),
    border: Color(0xFFF0DCCB),
    borderStrong: Color(0xFFE0C3AB),
    textPrimary: Color(0xFF24150D),
    textSecondary: Color(0xFF7A6154),
    textTertiary: Color(0xFF9C8477),
    accent: Color(0xFFE8540B),
    onAccent: Color(0xFFFFFFFF),
    accentText: Color(0xFFA8400A),
    accentSurface: Color(0xFFFFEAD9),
    accentBorder: Color(0xFFF5C6A3),
    codeComment: Color(0xFF7C6556),
    codeKeyword: Color(0xFFB23A0B),
    codeString: Color(0xFF2F6B22),
    codeNumber: Color(0xFF8A5A0F),
    codeCall: Color(0xFF15618F),
  );

  @override
  FoxPalette copyWith({
    Color? background,
    Color? surfaceRaised,
    Color? surfaceInput,
    Color? surfaceSelected,
    Color? userBubble,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? onAccent,
    Color? accentText,
    Color? accentSurface,
    Color? accentBorder,
    Color? codeComment,
    Color? codeKeyword,
    Color? codeString,
    Color? codeNumber,
    Color? codeCall,
  }) {
    return FoxPalette(
      background: background ?? this.background,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceInput: surfaceInput ?? this.surfaceInput,
      surfaceSelected: surfaceSelected ?? this.surfaceSelected,
      userBubble: userBubble ?? this.userBubble,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentText: accentText ?? this.accentText,
      accentSurface: accentSurface ?? this.accentSurface,
      accentBorder: accentBorder ?? this.accentBorder,
      codeComment: codeComment ?? this.codeComment,
      codeKeyword: codeKeyword ?? this.codeKeyword,
      codeString: codeString ?? this.codeString,
      codeNumber: codeNumber ?? this.codeNumber,
      codeCall: codeCall ?? this.codeCall,
    );
  }

  @override
  FoxPalette lerp(covariant FoxPalette? other, double t) {
    if (other == null) {
      return this;
    }
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return FoxPalette(
      background: mix(background, other.background),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      surfaceInput: mix(surfaceInput, other.surfaceInput),
      surfaceSelected: mix(surfaceSelected, other.surfaceSelected),
      userBubble: mix(userBubble, other.userBubble),
      border: mix(border, other.border),
      borderStrong: mix(borderStrong, other.borderStrong),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textTertiary: mix(textTertiary, other.textTertiary),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      accentText: mix(accentText, other.accentText),
      accentSurface: mix(accentSurface, other.accentSurface),
      accentBorder: mix(accentBorder, other.accentBorder),
      codeComment: mix(codeComment, other.codeComment),
      codeKeyword: mix(codeKeyword, other.codeKeyword),
      codeString: mix(codeString, other.codeString),
      codeNumber: mix(codeNumber, other.codeNumber),
      codeCall: mix(codeCall, other.codeCall),
    );
  }
}

extension FoxPaletteAccess on BuildContext {
  /// Palette FoxGPT du thème courant.
  ///
  /// Retombe sur la déclinaison correspondant à la luminosité ambiante si
  /// l'extension est absente, pour qu'un widget monté hors du thème FoxGPT
  /// s'affiche au lieu de lever.
  FoxPalette get fox {
    final theme = Theme.of(this);
    return theme.extension<FoxPalette>() ??
        (theme.brightness == Brightness.dark
            ? FoxPalette.dark
            : FoxPalette.light);
  }
}
