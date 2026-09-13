// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fox_theme.dart';

/// Déclare au système Android la déclinaison choisie dans l'application.
///
/// La fenêtre de lancement — celle qui porte le renard — est dessinée par
/// Android avant même que le processus démarre : elle ne peut donc pas lire une
/// préférence de l'application, et restait noire quel que soit le thème.
/// Depuis Android 12, `UiModeManager.setApplicationNightMode` annonce au
/// système le mode de l'application ; il résout alors les ressources
/// `values-night` — dont la couleur du splash — en conséquence, dès le
/// lancement suivant.
class SystemAppearance {
  const SystemAppearance();

  static const MethodChannel channel = MethodChannel('foxgpt/appearance');

  /// Annonce le mode au système sans attendre sa réponse.
  ///
  /// Rien ne dépend du résultat, et attendre un canal de plateforme depuis le
  /// changement de thème le bloquerait là où ce canal n'existe pas : autres
  /// systèmes, et bancs de test, dont l'horloge simulée ne délivre jamais la
  /// réponse.
  void apply(FoxTheme theme) {
    unawaited(
      channel
          .invokeMethod<void>(
            'setDarkMode',
            theme.brightness == Brightness.dark,
          )
          .catchError((Object _) {
            // Hors Android, ou avant Android 12 : la fenêtre de lancement suit
            // le mode sombre du système, faute de pouvoir être choisie.
          }),
    );
  }
}

final systemAppearanceProvider = Provider<SystemAppearance>(
  (ref) => const SystemAppearance(),
);
