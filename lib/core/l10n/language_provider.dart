// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:foxllm/core/l10n/fox_language.dart';

/// Conserve la langue choisie entre deux lancements.
///
/// Même stockage que la déclinaison, pour la même raison : une préférence de
/// plus ne justifie pas une dépendance de plus.
class FoxLanguageStore {
  FoxLanguageStore({FlutterSecureStorage? storage})
    : _storage = storage ?? FlutterSecureStorage();

  static const _key = 'foxllm.appearance.language';

  final FlutterSecureStorage _storage;

  Future<FoxLanguage> load() async {
    final stored = await _storage.read(key: _key);
    return FoxLanguage.values.firstWhere(
      (language) => language.name == stored,
      orElse: () => FoxLanguage.system,
    );
  }

  Future<void> save(FoxLanguage language) =>
      _storage.write(key: _key, value: language.name);
}

final foxLanguageStoreProvider = Provider<FoxLanguageStore>(
  (ref) => FoxLanguageStore(),
);

final foxLanguageProvider =
    NotifierProvider<FoxLanguageController, FoxLanguage>(
      FoxLanguageController.new,
    );

class FoxLanguageController extends Notifier<FoxLanguage> {
  /// Vrai dès que l'utilisateur a choisi une langue dans cette session.
  bool _selected = false;

  @override
  FoxLanguage build() {
    // La langue de l'appareil s'applique immédiatement, puis le choix
    // enregistré la remplace : lire le stockage est asynchrone et ne doit pas
    // retarder le premier frame.
    _selected = false;
    _restore();
    return FoxLanguage.system;
  }

  Future<void> _restore() async {
    try {
      final stored = await ref.read(foxLanguageStoreProvider).load();
      // Une lecture lente ne doit pas revenir par-dessus un choix fait
      // entre-temps, sinon la langue repasserait toute seule à l'ancienne.
      if (_selected || stored == state) {
        return;
      }
      state = stored;
    } catch (_) {
      // Préférence illisible : la langue de l'appareil reste en place.
    }
  }

  Future<void> select(FoxLanguage language) async {
    _selected = true;
    if (state != language) {
      state = language;
    }
    try {
      await ref.read(foxLanguageStoreProvider).save(language);
    } catch (_) {
      // Le choix s'applique quand même pour la session en cours.
    }
  }
}
