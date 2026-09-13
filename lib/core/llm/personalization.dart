// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Longueur maximale des instructions personnalisées.
///
/// Elles sont renvoyées à chaque requête et consomment donc la fenêtre de
/// contexte à chaque tour. Au-delà, il resterait trop peu de place pour la
/// conversation elle-même sur un modèle local.
const int maxInstructionsLength = 2000;

/// Conserve les instructions que l'utilisateur donne à son IA.
///
/// Le stockage sécurisé est déjà celui des autres préférences : s'y adosser
/// évite une dépendance de plus pour une simple chaîne.
class PersonalizationStore {
  PersonalizationStore({FlutterSecureStorage? storage})
    : _storage = storage ?? FlutterSecureStorage();

  static const _key = 'foxgpt.personalization.instructions';

  final FlutterSecureStorage _storage;

  Future<String> load() async => await _storage.read(key: _key) ?? '';

  Future<void> save(String instructions) {
    final trimmed = instructions.trim();
    if (trimmed.isEmpty) {
      return _storage.delete(key: _key);
    }
    return _storage.write(key: _key, value: trimmed);
  }
}

/// Exemple prêt à l'emploi, pour ne pas laisser l'utilisateur devant une page
/// blanche.
class PersonalizationPreset {
  const PersonalizationPreset({
    required this.label,
    required this.instructions,
  });

  final String label;
  final String instructions;
}

const List<PersonalizationPreset> personalizationPresets =
    <PersonalizationPreset>[
      PersonalizationPreset(
        label: 'Réponses courtes',
        instructions:
            'Réponds de façon brève et directe. Va à l’essentiel, sans '
            'introduction ni conclusion superflue.',
      ),
      PersonalizationPreset(
        label: 'Pédagogue',
        instructions:
            'Explique comme à un débutant : vocabulaire simple, un exemple '
            'concret par notion, et termine par une question pour vérifier '
            'que j’ai compris.',
      ),
      PersonalizationPreset(
        label: 'Expert technique',
        instructions:
            'Réponds comme un ingénieur expérimenté : sois précis, signale '
            'les pièges et les cas limites, et donne du code complet quand '
            'c’est utile.',
      ),
      PersonalizationPreset(
        label: 'Ton amical',
        instructions:
            'Adopte un ton chaleureux et encourageant, tutoie-moi, et garde '
            'des réponses vivantes.',
      ),
    ];

final personalizationStoreProvider = Provider<PersonalizationStore>(
  (ref) => PersonalizationStore(),
);

/// Instructions actives, envoyées au modèle en message système.
final personalizationProvider =
    NotifierProvider<PersonalizationController, String>(
      PersonalizationController.new,
    );

class PersonalizationController extends Notifier<String> {
  late Future<void> _restored;

  /// Vrai dès que l'utilisateur a enregistré quelque chose dans cette session.
  bool _edited = false;

  @override
  String build() {
    // Le chat s'affiche sans attendre le stockage : les instructions arrivent
    // ensuite, et `resolved()` garantit qu'un envoi ne parte jamais avant.
    _edited = false;
    _restored = _restore();
    return '';
  }

  Future<void> _restore() async {
    try {
      final stored = await ref.read(personalizationStoreProvider).load();
      // Une lecture lente ne doit pas revenir par-dessus une saisie faite
      // entre-temps : l'utilisateur a toujours le dernier mot.
      if (!_edited && stored != state) {
        state = stored;
      }
    } catch (_) {
      // Préférence illisible : l'IA répond sans instruction particulière.
    }
  }

  /// Instructions une fois la lecture du stockage terminée.
  Future<String> resolved() async {
    await _restored;
    return state;
  }

  Future<void> save(String instructions) async {
    _edited = true;
    final trimmed = instructions.trim();
    final capped = trimmed.length > maxInstructionsLength
        ? trimmed.substring(0, maxInstructionsLength)
        : trimmed;
    state = capped;
    try {
      await ref.read(personalizationStoreProvider).save(capped);
    } catch (_) {
      // Le choix s'applique quand même à la session en cours.
    }
  }
}
