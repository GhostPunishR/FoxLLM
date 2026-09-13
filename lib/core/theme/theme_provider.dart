// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:foxllm/core/theme/fox_theme.dart';
import 'package:foxllm/core/theme/system_appearance.dart';

/// Conserve la déclinaison choisie entre deux lancements.
///
/// Le stockage sécurisé est déjà utilisé par les réglages d'API personnelle :
/// s'y adosser évite d'ajouter une dépendance pour une simple préférence.
class FoxThemeStore {
  FoxThemeStore({FlutterSecureStorage? storage})
    : _storage = storage ?? FlutterSecureStorage();

  static const _key = 'foxllm.appearance.theme';

  final FlutterSecureStorage _storage;

  Future<FoxTheme> load() async {
    final stored = await _storage.read(key: _key);
    return FoxTheme.values.firstWhere(
      (theme) => theme.name == stored,
      orElse: () => FoxTheme.light,
    );
  }

  Future<void> save(FoxTheme theme) =>
      _storage.write(key: _key, value: theme.name);
}

final foxThemeStoreProvider = Provider<FoxThemeStore>((ref) => FoxThemeStore());

final foxThemeProvider = NotifierProvider<FoxThemeController, FoxTheme>(
  FoxThemeController.new,
);

class FoxThemeController extends Notifier<FoxTheme> {
  /// Vrai dès que l'utilisateur a choisi une déclinaison dans cette session.
  bool _selected = false;

  @override
  FoxTheme build() {
    // Le thème clair s'affiche immédiatement, puis le choix enregistré le
    // remplace : lire le stockage est asynchrone et ne doit pas retarder le
    // premier frame.
    _selected = false;
    _restore();
    return FoxTheme.light;
  }

  Future<void> _restore() async {
    try {
      final stored = await ref.read(foxThemeStoreProvider).load();
      // Une lecture lente ne doit pas revenir par-dessus un choix fait
      // entre-temps, sinon le thème repasserait tout seul à l'ancien.
      if (_selected) {
        return;
      }
      if (stored != state) {
        state = stored;
      }
      // Le système peut ignorer le mode de l'application (réinstallation,
      // effacement des données) : on le lui redit à chaque lancement, sinon la
      // fenêtre de lancement repartirait sur la déclinaison claire.
      ref.read(systemAppearanceProvider).apply(stored);
    } catch (_) {
      // Préférence illisible : le thème clair par défaut reste en place.
    }
  }

  Future<void> select(FoxTheme theme) async {
    _selected = true;
    if (state != theme) {
      state = theme;
    }
    // La fenêtre de lancement d'Android suivra dès le prochain démarrage.
    ref.read(systemAppearanceProvider).apply(theme);
    try {
      await ref.read(foxThemeStoreProvider).save(theme);
    } catch (_) {
      // Le choix s'applique quand même pour la session en cours.
    }
  }
}
