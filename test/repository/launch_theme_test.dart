// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// La fenêtre de lancement est dessinée par Android avant que le processus
/// démarre : elle suit la déclinaison déclarée au système, jamais une
/// préférence lue par l'application. Ces contrôles gardent en place ce qui
/// fait que cette déclaration arrive assez tôt.
///
/// Ils portent sur la source : le comportement lui-même ne se vérifie que sur
/// un appareil, et aucun test de ce dépôt ne s'exécute sur Android.
void main() {
  final activity = File(
    'android/app/src/main/kotlin/com/ghostpunishr/foxllm/MainActivity.kt',
  ).readAsStringSync();

  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();

  test('le mode est déclaré à l’ouverture, pas seulement par le canal', () {
    // Déclaré depuis le seul canal, le mode n'arrivait qu'après le démarrage
    // du moteur Flutter et une lecture du stockage chiffré : trop tard pour la
    // fenêtre de lancement, et perdu si l'une des deux échouait.
    final onCreate = activity.indexOf('override fun onCreate(');
    final configure = activity.indexOf('override fun configureFlutterEngine(');
    expect(onCreate, greaterThan(0), reason: 'onCreate n’est plus surchargée');

    final body = activity.substring(onCreate, configure);
    expect(
      body,
      contains('applyNightMode('),
      reason: 'le mode n’est plus déclaré à l’ouverture de l’activité',
    );
    expect(
      body.indexOf('applyNightMode('),
      lessThan(body.indexOf('super.onCreate(')),
      reason: 'déclaré après super.onCreate, le thème est déjà choisi',
    );
  });

  test('le choix est gardé côté natif pour le lancement suivant', () {
    // Le stockage de Flutter est chiffré et ne se lit pas avant le moteur :
    // une copie ordinaire est ce qui permet de déclarer le mode à l'ouverture.
    expect(activity, contains('getSharedPreferences('));
    expect(activity, contains('putBoolean('));
    expect(activity, contains('getBoolean('));
  });

  test('le défaut du premier lancement reste la déclinaison claire', () {
    // Rien n'est encore enregistré au premier lancement : c'est ce `false` qui
    // dit au système que l'application s'ouvre en clair.
    expect(activity, contains('getBoolean(DARK_KEY, false)'));
  });

  test('uiMode reste déclaré dans les configChanges', () {
    // Déclarer le mode peut provoquer un changement de configuration. Sans
    // `uiMode` ici, Android recréerait l'activité en plein démarrage.
    final configChanges = RegExp(
      r'android:configChanges="([^"]+)"',
    ).firstMatch(manifest);
    expect(configChanges, isNotNull);
    expect(configChanges!.group(1), contains('uiMode'));
  });
}
