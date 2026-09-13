// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Dossiers dont FoxLLM écrit lui-même le contenu, avec les extensions
/// concernées. `LICENSE` en est absent : son texte est repris mot pour mot de
/// la Free Software Foundation et ne doit pas être retouché.
const _ownedRoots = <String, List<String>>{
  'lib': <String>['.dart'],
  'test': <String>['.dart'],
  'docs': <String>['.html', '.css', '.js'],
  'packages/foxllm_native/lib': <String>['.dart'],
  'packages/foxllm_native/tool': <String>['.dart'],
  'packages/foxllm_native/hook': <String>['.dart'],
  'packages/foxllm_native/src': <String>['.cpp', '.h'],
  'android/app/src/main/kotlin': <String>['.kt'],
};

const _ownedFiles = <String>['README.md', 'CHANGELOG.md'];

String _entity(String name) => '&$name;';

/// Tirets longs, assemblés plutôt qu'écrits en clair afin que ce fichier ne
/// contienne aucun des motifs qu'il interdit.
final _bannedDashes = <String, String>{
  String.fromCharCode(0x2014): 'tiret cadratin',
  String.fromCharCode(0x2013): 'tiret demi-cadratin',
  _entity('mdash'): 'entité HTML du tiret cadratin',
  _entity('ndash'): 'entité HTML du tiret demi-cadratin',
  _entity('#8212'): 'entité numérique du tiret cadratin',
};

Iterable<File> _ownedSources() sync* {
  for (final entry in _ownedRoots.entries) {
    final directory = Directory(entry.key);
    if (!directory.existsSync()) {
      continue;
    }
    for (final file in directory.listSync(recursive: true).whereType<File>()) {
      if (entry.value.any(file.path.endsWith)) {
        yield file;
      }
    }
  }
  for (final name in _ownedFiles) {
    final file = File(name);
    if (file.existsSync()) {
      yield file;
    }
  }
}

void main() {
  test('aucun tiret long dans les fichiers du dépôt', () {
    // Le tiret cadratin est proscrit ici : il rend les phrases plus lourdes à
    // lire et se copie mal d'un éditeur à l'autre. Deux-points, virgules et
    // parenthèses font le même travail.
    final offenders = <String>[];

    for (final file in _ownedSources()) {
      final lines = file.readAsStringSync().split('\n');
      for (var index = 0; index < lines.length; index++) {
        for (final entry in _bannedDashes.entries) {
          if (lines[index].contains(entry.key)) {
            offenders.add('${file.path}:${index + 1} (${entry.value})');
          }
        }
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
