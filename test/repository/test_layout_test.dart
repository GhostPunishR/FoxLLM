// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Le dépôt porte deux paquets Dart, et donc deux dossiers `test` : celui de
/// la racine appartient à l'application, celui de `packages/foxllm_native` au
/// pont natif. Ce n'est pas un éparpillement, c'est la règle des paquets
/// Dart : `flutter test` à la racine n'exécute que les tests de
/// l'application, et un fichier C++ posé là ne serait jamais lancé.
///
/// Ce qui serait un éparpillement, en revanche, c'est qu'un paquet range ses
/// tests ailleurs que dans son `test`. C'était le cas du pont natif, dont la
/// moitié des vérifications vivaient dans `tool`.
void main() {
  final tracked = Process.runSync('git', <String>[
    'ls-files',
  ], workingDirectory: '.').stdout.toString().trim().split('\n');

  test('chaque vérification vit dans un dossier `test`', () {
    final stray = tracked
        .where(
          (path) =>
              path.contains('_test.') ||
              path.contains('smoke') ||
              path.contains('/asan/'),
        )
        .where((path) => !path.split('/').contains('test'))
        // Les fichiers d'intégration continue nomment les tests sans en être.
        .where((path) => !path.startsWith('.github/'))
        .toList();

    expect(
      stray,
      isEmpty,
      reason:
          'vérifications rangées hors d’un dossier `test` : $stray. Le paquet '
          'qui les porte doit les accueillir dans le sien.',
    );
  });

  test(
    'les travaux d’intégration continue visent des fichiers qui existent',
    () {
      // Déplacer une vérification sans corriger le travail qui l'exécute casse
      // l'intégration continue plutôt que le dépôt : l'erreur n'apparaît qu'une
      // fois poussée.
      const native = 'packages/foxllm_native';
      final referenced = <String, String>{
        '.github/workflows/ffi-smoke.yml': '$native/test/native_smoke.dart',
        '.github/workflows/cpp.yml': '$native/test/cache_decisions_test.cpp',
      };

      referenced.forEach((workflow, target) {
        final relative = target.substring('$native/'.length);
        expect(
          File(workflow).readAsStringSync(),
          contains(relative),
          reason: '$workflow ne mentionne plus $relative',
        );
        expect(
          File(target).existsSync(),
          isTrue,
          reason: '$workflow exécute $target, qui n’existe pas',
        );
      });
    },
  );
}
