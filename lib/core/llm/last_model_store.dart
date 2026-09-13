// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Retient le dernier modèle GGUF chargé, pour le remettre en place au
/// lancement suivant sans que l'utilisateur ait à repasser par l'écran des
/// modèles locaux.
class LastModelStore {
  LastModelStore({FlutterSecureStorage? storage})
    : _storage = storage ?? FlutterSecureStorage();

  static const _key = 'foxgpt.local_model.last_path';

  final FlutterSecureStorage _storage;

  /// Chemin mémorisé, uniquement s'il désigne toujours un fichier existant.
  ///
  /// Le modèle a pu être supprimé depuis, ou l'application réinstallée : un
  /// chemin périmé doit être oublié plutôt que de faire échouer un chargement.
  Future<String?> load() async {
    final path = await _storage.read(key: _key);
    if (path == null || path.isEmpty) {
      return null;
    }
    if (!await File(path).exists()) {
      await clear();
      return null;
    }
    return path;
  }

  Future<void> save(String path) => _storage.write(key: _key, value: path);

  Future<void> clear() => _storage.delete(key: _key);
}

final lastModelStoreProvider = Provider<LastModelStore>(
  (ref) => LastModelStore(),
);
