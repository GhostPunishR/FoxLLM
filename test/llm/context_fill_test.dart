// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm_native/foxllm_native.dart';

/// Le remplissage du contexte, relevé sur le cache KV du moteur.
///
/// Jusqu'ici, rien n'annonçait qu'une conversation approchait de la fenêtre du
/// modèle : le refus arrivait sans prévenir, et en anglais. La mesure existe
/// désormais, exacte plutôt qu'estimée à partir du nombre de caractères.
void main() {
  FoxLlmGenerationStats stats({
    int used = 0,
    int capacity = 0,
    int tokens = 10,
  }) => FoxLlmGenerationStats(
    generatedTokens: tokens,
    elapsed: const Duration(seconds: 1),
    contextUsed: used,
    contextCapacity: capacity,
  );

  test('la part occupée est le rapport des deux comptes', () {
    expect(stats(used: 512, capacity: 2048).contextFill, 0.25);
    expect(stats(used: 1024, capacity: 4096).contextFill, 0.25);
  });

  test('elle est inconnue tant qu’il manque un des deux', () {
    // Une API personnelle ne rend aucun de ces comptes : sa réponse ne doit
    // pas afficher « contexte 0 % », qui serait faux plutôt que muet.
    expect(stats().contextFill, isNull);
    expect(stats(used: 100).contextFill, isNull);
    expect(stats(capacity: 4096).contextFill, isNull);
  });

  test('elle ne dépasse jamais un', () {
    // Le contexte réellement alloué peut dépasser celui de l'entraînement :
    // un rapport supérieur à un donnerait « contexte 130 % ».
    expect(stats(used: 5000, capacity: 4096).contextFill, 1.0);
  });

  test('les valeurs par défaut n’inventent rien', () {
    const bare = FoxLlmGenerationStats(
      generatedTokens: 5,
      elapsed: Duration(seconds: 1),
    );
    expect(bare.contextUsed, 0);
    expect(bare.contextCapacity, 0);
    expect(bare.contextFill, isNull);
  });
}
