import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/last_model_store.dart';
import 'local_model_file.dart';

/// Nom du modèle GGUF en place, ou `null` si aucun.
///
/// Lu depuis le chemin mémorisé plutôt que depuis le moteur : interroger
/// `LocalLlmBackend` le construirait — isolate worker et `llama.cpp` compris —
/// pour le seul besoin d'afficher un sous-titre. Le chemin est enregistré au
/// chargement d'un modèle et effacé à son déchargement, il désigne donc bien
/// celui qui répondra au prochain message.
final currentLocalModelProvider = FutureProvider<String?>((ref) async {
  final path = await ref.watch(lastModelStoreProvider).load();
  return path == null ? null : localModelDisplayName(path);
});
