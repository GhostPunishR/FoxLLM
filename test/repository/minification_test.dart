// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// La minification de la distribution, et ce qu'elle doit épargner.
///
/// R8 supprime ce qu'il croit inatteignable. Une règle manquante ne casse pas
/// la compilation : l'APK sort, s'installe, et échoue ensuite chez
/// l'utilisateur. L'intégration continue ne peut donc pas l'attraper, et ces
/// contrôles ne remplacent pas un essai sur appareil. Ils garantissent
/// seulement que la configuration ne se perd pas en silence.
void main() {
  const gradle = 'android/app/build.gradle.kts';
  const rules = 'android/app/proguard-rules.pro';

  test('la distribution est minifiée, et ses ressources réduites', () {
    final contents = File(gradle).readAsStringSync();

    expect(contents, contains('isMinifyEnabled = true'));
    expect(contents, contains('isShrinkResources = true'));
    expect(contents, contains('proguard-rules.pro'));
  });

  test('le fichier de règles existe là où gradle le cherche', () {
    // Une référence à un fichier absent passe la compilation sans appliquer
    // la moindre règle : le pire des deux mondes.
    expect(File(rules).existsSync(), isTrue, reason: '$rules introuvable');
  });

  test('les règles épargnent ce qui n’est atteint que par réflexion', () {
    final contents = File(rules).readAsStringSync();

    // Flutter et ses canaux, l'activité nommée dans le manifeste, les deux
    // services vocaux du système et le stockage sécurisé : tout ce qui entre
    // dans l'application sans qu'aucun appel Dart ne le désigne.
    for (final kept in <String>[
      'io.flutter.',
      'com.ghostpunishr.foxllm.',
      'android.speech.',
      'androidx.security.crypto.',
    ]) {
      expect(
        contents,
        contains(kept),
        reason: '$kept n’est pas épargné par R8',
      );
    }
  });

  test('les traces d’erreur restent lisibles', () {
    // Sans cela, un incident rapporté par un utilisateur ne désignerait que
    // des noms d'une lettre, et serait indiagnosticable.
    final contents = File(rules).readAsStringSync();

    expect(contents, contains('SourceFile'));
    expect(contents, contains('LineNumberTable'));
  });
}
