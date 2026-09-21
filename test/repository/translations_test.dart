// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Les deux fichiers de traduction, l'un en face de l'autre.
///
/// Le français est la langue source : c'est dans `app_fr.arb` que les textes
/// sont écrits, et `app_en.arb` en donne la traduction. Rien n'oblige les deux
/// à rester appariés, et une clé ajoutée d'un seul côté ne casse pas la
/// génération : elle fait simplement ressortir du français dans une interface
/// anglaise, ce qu'aucune relecture ne remarque.
void main() {
  const french = 'lib/l10n/app_fr.arb';
  const english = 'lib/l10n/app_en.arb';

  /// Les clés d'un fichier ARB, sans les métadonnées `@`.
  Set<String> keysOf(String path) {
    final decoded = jsonDecode(File(path).readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      fail('$path ne contient pas un objet JSON');
    }
    return decoded.keys.where((key) => !key.startsWith('@')).toSet();
  }

  test('les deux fichiers existent', () {
    for (final path in <String>[french, english]) {
      expect(File(path).existsSync(), isTrue, reason: '$path introuvable');
    }
  });

  test('chaque texte français a sa traduction anglaise', () {
    final missing = keysOf(french).difference(keysOf(english));

    expect(
      missing,
      isEmpty,
      reason:
          'clés sans traduction anglaise : $missing. Elles ressortiraient en '
          'français dans une interface anglaise.',
    );
  });

  test('aucune traduction anglaise ne vise un texte disparu', () {
    // L'inverse compte aussi : une clé orpheline survit aux suppressions et
    // laisse croire qu'un texte existe encore.
    final orphans = keysOf(english).difference(keysOf(french));

    expect(orphans, isEmpty, reason: 'clés anglaises sans source : $orphans');
  });

  test('aucun texte n’est vide', () {
    for (final path in <String>[french, english]) {
      final decoded =
          jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
      final empty = decoded.entries
          .where((entry) => !entry.key.startsWith('@'))
          .where((entry) => (entry.value as String).trim().isEmpty)
          .map((entry) => entry.key)
          .toList();

      expect(empty, isEmpty, reason: '$path : clés au texte vide : $empty');
    }
  });

  test('les substitutions se retrouvent des deux côtés', () {
    // Un `{name}` oublié dans la traduction laisse un trou à l'écran, et un
    // `{name}` en trop fait lever la génération à l'exécution.
    final fr =
        jsonDecode(File(french).readAsStringSync()) as Map<String, Object?>;
    final en =
        jsonDecode(File(english).readAsStringSync()) as Map<String, Object?>;
    final pattern = RegExp(r'\{(\w+)\}');
    final mismatched = <String>[];

    for (final entry in fr.entries) {
      if (entry.key.startsWith('@')) {
        continue;
      }
      final translated = en[entry.key];
      if (translated is! String) {
        continue;
      }
      final source = pattern
          .allMatches(entry.value! as String)
          .map((match) => match.group(1)!)
          .toSet();
      final target = pattern
          .allMatches(translated)
          .map((match) => match.group(1)!)
          .toSet();
      if (source.difference(target).isNotEmpty ||
          target.difference(source).isNotEmpty) {
        mismatched.add('${entry.key} : $source contre $target');
      }
    }

    expect(mismatched, isEmpty, reason: mismatched.join('\n'));
  });
}
