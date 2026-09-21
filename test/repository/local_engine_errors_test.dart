// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:foxllm/l10n/app_localizations.dart';
import 'package:foxllm/llm/backend/local_engine_error.dart';

/// Le pont natif ne rend qu'une chaîne anglaise, faute de code d'erreur dans
/// son interface. `LocalEngineFailure` la reconnaît pour la traduire, ce qui
/// est fragile par nature : un message ajouté au C++ et oublié ici
/// ressortirait en anglais dans le bandeau du chat, sans que rien ne le
/// signale.
///
/// Ce contrôle relit le C++ et refuse ce silence. C'est lui qui rend la
/// correspondance tenable.
void main() {
  const source = 'packages/foxllm_native/src/foxllm_native.cpp';

  /// Toutes les chaînes affectées à `last_error`, ternaires comprises.
  Set<String> nativeMessages() {
    final contents = File(source).readAsStringSync();
    final found = <String>{};
    // Une affectation, puis tout ce qui la suit jusqu'au point-virgule : cela
    // couvre aussi bien `last_error = "..."` que la forme ternaire, qui porte
    // deux messages sur trois lignes.
    for (final assignment in RegExp(
      r'last_error\s*=([^;]*);',
      dotAll: true,
    ).allMatches(contents)) {
      for (final literal in RegExp(
        r'"([^"]{6,})"',
      ).allMatches(assignment.group(1)!)) {
        found.add(literal.group(1)!);
      }
    }
    return found;
  }

  test('le fichier natif est bien là où on le cherche', () {
    // Sans cela, un déplacement du source rendrait le contrôle suivant vert
    // en ne lisant plus rien.
    expect(File(source).existsSync(), isTrue, reason: '$source introuvable');
    expect(nativeMessages(), isNotEmpty);
  });

  test('chaque message du moteur local a sa traduction', () {
    final known = LocalEngineFailure.values
        .map((failure) => failure.nativeMessage)
        .toSet();
    final untranslated = nativeMessages().difference(known);

    expect(
      untranslated,
      isEmpty,
      reason:
          'messages du C++ sans traduction : $untranslated. Ajoutez-les à '
          'LocalEngineFailure et aux fichiers ARB, sinon ils s’affichent en '
          'anglais dans le chat.',
    );
  });

  test('aucune traduction ne vise un message disparu', () {
    // L'inverse compte aussi : une entrée qui ne correspond plus à rien
    // laisserait croire qu'un cas est couvert alors qu'il a changé de texte.
    final messages = nativeMessages();
    final orphans = LocalEngineFailure.values
        .map((failure) => failure.nativeMessage)
        .where((message) => !messages.contains(message))
        .toList();

    expect(orphans, isEmpty, reason: 'traductions sans message : $orphans');
  });

  test('les deux langues rendent chaque message', () {
    for (final locale in <Locale>[Locale('fr'), Locale('en')]) {
      final l10n = lookupAppLocalizations(locale);
      for (final failure in LocalEngineFailure.values) {
        expect(
          failure.describe(l10n),
          isNotEmpty,
          reason:
              '${failure.name} n\u2019a rien \u00e0 dire en ${locale.languageCode}',
        );
      }
    }
  });

  test('le fran\u00e7ais ne laisse passer aucun message anglais', () {
    // L'affirmation ne vaut que pour le fran\u00e7ais : en anglais, la traduction
    // d'un message d\u00e9j\u00e0 anglais peut l\u00e9gitimement lui \u00eatre identique, comme
    // « No message to format. ». C'est ce que ce contr\u00f4le a d'abord signal\u00e9
    // \u00e0 tort.
    final l10n = lookupAppLocalizations(const Locale('fr'));
    for (final failure in LocalEngineFailure.values) {
      expect(
        failure.describe(l10n),
        isNot(failure.nativeMessage),
        reason:
            '${failure.name} rend le message natif tel quel en fran\u00e7ais',
      );
    }
  });

  test('la reconnaissance tolère les espaces, et rien d’autre', () {
    expect(
      LocalEngineFailure.match('  Prompt is empty.  '),
      LocalEngineFailure.emptyPrompt,
    );
    expect(LocalEngineFailure.match('Prompt is empty'), isNull);
    expect(LocalEngineFailure.match('autre chose'), isNull);
    expect(LocalEngineFailure.match(''), isNull);
  });
}
