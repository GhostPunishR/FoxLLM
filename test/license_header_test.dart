// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Dossiers dont FoxGPT écrit lui-même le contenu.
const _ownedRoots = <String, List<String>>{
  'lib': <String>['.dart'],
  'test': <String>['.dart'],
  'packages/foxgpt_native/lib': <String>['.dart'],
  'packages/foxgpt_native/tool': <String>['.dart'],
  'packages/foxgpt_native/hook': <String>['.dart'],
  'packages/foxgpt_native/src': <String>['.cpp', '.h'],
  'android/app/src/main/kotlin': <String>['.kt'],
};

void main() {
  test('chaque fichier source porte la notice de licence', () {
    // L'AGPL demande d'attacher la notice aux fichiers du programme : sans
    // garde, un fichier ajouté plus tard passerait au travers sans qu'on s'en
    // aperçoive.
    final missing = <String>[];

    for (final entry in _ownedRoots.entries) {
      final directory = Directory(entry.key);
      if (!directory.existsSync()) {
        continue;
      }
      for (final file
          in directory.listSync(recursive: true).whereType<File>()) {
        if (!entry.value.any(file.path.endsWith)) {
          continue;
        }
        final head = file.readAsStringSync();
        if (!head.startsWith('// Copyright © ') ||
            !head.contains('// SPDX-License-Identifier: AGPL-3.0-or-later')) {
          missing.add(file.path);
        }
      }
    }

    expect(
      missing,
      isEmpty,
      reason: 'notice absente de : ${missing.join(', ')}',
    );
  });

  test('le texte de la licence reste celui de la FSF', () {
    // La ligne de l'annexe est un modèle à recopier dans les fichiers du
    // programme, pas un champ à remplir : la remplacer modifierait le texte de
    // la licence, et la notice de FoxGPT vit dans ses propres fichiers.
    final license = File('LICENSE').readAsStringSync();

    expect(license, contains('Copyright (C) 2007 Free Software Foundation'));
    expect(license, contains('Copyright (C) <year>  <name of author>'));
    expect(license, isNot(contains('GhostPunishR')));
  });
}
