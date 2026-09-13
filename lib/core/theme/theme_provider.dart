import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'fox_theme.dart';

/// Conserve la déclinaison choisie entre deux lancements.
///
/// Le stockage sécurisé est déjà utilisé par les réglages d'API personnelle :
/// s'y adosser évite d'ajouter une dépendance pour une simple préférence.
class FoxThemeStore {
  FoxThemeStore({FlutterSecureStorage? storage})
    : _storage = storage ?? FlutterSecureStorage();

  static const _key = 'foxgpt.appearance.theme';

  final FlutterSecureStorage _storage;

  Future<FoxTheme> load() async {
    final stored = await _storage.read(key: _key);
    return FoxTheme.values.firstWhere(
      (theme) => theme.name == stored,
      orElse: () => FoxTheme.dark,
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
    // Le thème sombre s'affiche immédiatement, puis le choix enregistré le
    // remplace : lire le stockage est asynchrone et ne doit pas retarder le
    // premier frame.
    _selected = false;
    _restore();
    return FoxTheme.dark;
  }

  Future<void> _restore() async {
    try {
      final stored = await ref.read(foxThemeStoreProvider).load();
      // Une lecture lente ne doit pas revenir par-dessus un choix fait
      // entre-temps, sinon le thème repasserait tout seul à l'ancien.
      if (!_selected && stored != state) {
        state = stored;
      }
    } catch (_) {
      // Préférence illisible : le thème sombre par défaut reste en place.
    }
  }

  Future<void> select(FoxTheme theme) async {
    _selected = true;
    if (state != theme) {
      state = theme;
    }
    try {
      await ref.read(foxThemeStoreProvider).save(theme);
    } catch (_) {
      // Le choix s'applique quand même pour la session en cours.
    }
  }
}
