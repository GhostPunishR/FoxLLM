// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:foxllm/l10n/app_localizations.dart';
import 'package:foxllm/llm/backend/backend_failure.dart';

/// Les refus levés hors de tout widget.
///
/// Les moteurs, les fournisseurs et la bibliothèque de modèles lèvent leurs
/// exceptions bien avant qu'un écran soit en vue : ils n'ont ni `context` ni
/// langue, et leur message est donc écrit en français dans le code.
/// `BackendFailure` le reconnaît pour le traduire, ce qui est fragile par
/// nature : reformuler une de ces phrases sans toucher à l'énumération la
/// ferait ressortir en français dans une interface anglaise, sans que rien ne
/// le signale.
void main() {
  /// Les fichiers qui portent ces refus.
  const sources = <String>[
    'lib/llm/personal_api/personal_api_settings.dart',
    'lib/llm/personal_api/personal_api_provider.dart',
    'lib/llm/backend/anthropic_backend.dart',
    'lib/llm/backend/openai_responses_backend.dart',
    'lib/features/local_models/local_model_library.dart',
    'lib/llm/personal_api/personal_api_settings_provider.dart',
  ];

  test('les fichiers surveillés existent tous', () {
    // Sans cela, un déplacement rendrait le contrôle suivant vert en ne
    // lisant plus rien.
    for (final source in sources) {
      expect(File(source).existsSync(), isTrue, reason: '$source introuvable');
    }
  });

  test('chaque phrase de l’énumération existe encore dans le code', () {
    final code = sources
        .map((path) => File(path).readAsStringSync())
        .join('\n');
    final orphans = BackendFailure.values
        .map((failure) => failure.message)
        .where((message) => !code.contains(message))
        .toList();

    expect(
      orphans,
      isEmpty,
      reason:
          'phrases traduites que plus aucun fichier ne lève : $orphans. '
          'Elles ont été reformulées ou supprimées, et la traduction ne les '
          'reconnaît plus.',
    );
  });

  test('les deux langues rendent chaque refus', () {
    for (final locale in <Locale>[Locale('fr'), Locale('en')]) {
      final l10n = lookupAppLocalizations(locale);
      for (final failure in BackendFailure.values) {
        expect(
          failure.describe(l10n),
          isNotEmpty,
          reason: '${failure.name} n’a rien à dire en ${locale.languageCode}',
        );
      }
    }
  });

  test('l’anglais ne laisse passer aucune phrase française', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    for (final failure in BackendFailure.values) {
      expect(
        failure.describe(l10n),
        isNot(failure.message),
        reason: '${failure.name} rend le texte français tel quel en anglais',
      );
    }
  });

  test('la reconnaissance tolère les espaces, et rien d’autre', () {
    expect(
      BackendFailure.match('  La réponse a échoué.  '),
      BackendFailure.responseFailed,
    );
    expect(BackendFailure.match('La réponse a échoué'), isNull);
    expect(BackendFailure.match('autre chose'), isNull);
  });

  group('clé API manquante', () {
    test('le nom du fournisseur est retrouvé', () {
      // Ce refus porte un nom variable : il ne peut pas figurer dans
      // l'énumération, qui compare des phrases entières.
      expect(
        missingApiKeyProvider('Aucune clé API configurée pour OpenAI.'),
        'OpenAI',
      );
      expect(
        missingApiKeyProvider('Aucune clé API configurée pour Mistral AI.'),
        'Mistral AI',
      );
    });

    test('et rien d’autre n’est pris pour ce refus', () {
      expect(missingApiKeyProvider('Aucune clé API configurée.'), isNull);
      expect(missingApiKeyProvider('La réponse a échoué.'), isNull);
      expect(missingApiKeyProvider(''), isNull);
    });

    test('la phrase reconnue est bien celle que le code lève', () {
      // Le motif est écrit à la main : s'il diverge de la phrase levée, la
      // reconnaissance échoue en silence et le français ressort.
      final code = sources
          .map((path) => File(path).readAsStringSync())
          .join('\n');
      expect(code, contains('Aucune clé API configurée pour '));
    });
  });
}
