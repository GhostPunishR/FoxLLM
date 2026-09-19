// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';

/// Rôles de couleur de FoxLLM, injectés dans le `ThemeData`.
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
    required this.codePlain,
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

  /// Orange FoxLLM, pour les aplats et actions principales.
  final Color accent;

  /// Contenu posé sur [accent].
  final Color onAccent;

  /// Orange lisible en texte ou en icône sur [accentSurface].
  final Color accentText;

  final Color accentSurface;
  final Color accentBorder;

  /// Coloration syntaxique des blocs de code du chat.
  ///
  /// Les teintes sont celles du thème Primer de GitHub, clair et sombre. Un
  /// extrait de code se lit partout ailleurs avec ces couleurs là : les
  /// reprendre évite d'avoir à réapprendre ce que veut dire un rouge ou un
  /// violet, et c'est vérifié lisible sur le fond des blocs de FoxLLM, qui
  /// n'est pas celui de GitHub.
  ///
  /// Le texte courant du code reprend [textPrimary] ; ces rôles ne portent que
  /// ce qui s'en détache. Chacun garde un contraste d'au moins 4,5:1 sur
  /// [surfaceInput], le fond des blocs.
  /// Texte d'un bloc de code que rien ne colore.
  ///
  /// Distinct de [textPrimary] : celui-ci porte la chaleur de FoxLLM, là où
  /// un bloc de code suit les couleurs de GitHub, que tout le monde reconnaît.
  final Color codePlain;
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
    codePlain: Color(0xFFF0F6FC),
    codeComment: Color(0xFF9198A1),
    codeKeyword: Color(0xFFFF7B72),
    codeString: Color(0xFFA5D6FF),
    codeNumber: Color(0xFF79C0FF),
    codeCall: Color(0xFFD2A8FF),
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
    textTertiary: Color(0xFF866E62),
    accent: Color(0xFFE8540B),
    onAccent: Color(0xFFFFFFFF),
    accentText: Color(0xFFA8400A),
    accentSurface: Color(0xFFFFEAD9),
    accentBorder: Color(0xFFF5C6A3),
    codePlain: Color(0xFF1F2328),
    codeComment: Color(0xFF59636E),
    codeKeyword: Color(0xFFCF222E),
    codeString: Color(0xFF0A3069),
    codeNumber: Color(0xFF0550AE),
    codeCall: Color(0xFF8250DF),
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
    Color? codePlain,
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
      codePlain: codePlain ?? this.codePlain,
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
      codePlain: mix(codePlain, other.codePlain),
      codeComment: mix(codeComment, other.codeComment),
      codeKeyword: mix(codeKeyword, other.codeKeyword),
      codeString: mix(codeString, other.codeString),
      codeNumber: mix(codeNumber, other.codeNumber),
      codeCall: mix(codeCall, other.codeCall),
    );
  }
}

extension FoxPaletteAccess on BuildContext {
  /// Palette FoxLLM du thème courant.
  ///
  /// Retombe sur la déclinaison correspondant à la luminosité ambiante si
  /// l'extension est absente, pour qu'un widget monté hors du thème FoxLLM
  /// s'affiche au lieu de lever.
  FoxPalette get fox {
    final theme = Theme.of(this);
    return theme.extension<FoxPalette>() ??
        (theme.brightness == Brightness.dark
            ? FoxPalette.dark
            : FoxPalette.light);
  }
}
