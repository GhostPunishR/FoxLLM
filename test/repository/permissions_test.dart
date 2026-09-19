// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/features/settings/about/legal_documents.dart';

/// La politique de confidentialité énumère les permissions de l'application.
/// Une permission ajoutée au manifeste sans un mot dans la politique rendrait
/// celle-ci fausse le jour de la publication : ces contrôles gardent les deux
/// d'accord, sur le manifeste source.
void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();

  final declared = RegExp(
    r'<uses-permission android:name="android\.permission\.([A-Z_]+)"',
  ).allMatches(manifest).map((match) => match.group(1)!).toSet();

  final policy = privacyPolicyDocument.sections
      .expand((section) => <String>[section.title, ...section.paragraphs])
      .join('\n');

  test('la politique décrit chaque permission déclarée', () {
    // Le mot attendu dans la politique pour chaque permission du manifeste.
    const described = <String, String>{
      'INTERNET': 'Internet',
      'RECORD_AUDIO': 'micro',
    };

    expect(
      declared.difference(described.keys.toSet()),
      isEmpty,
      reason:
          'permission ajoutée au manifeste sans être décrite dans la '
          'politique de confidentialité',
    );
    for (final permission in declared) {
      expect(
        policy,
        contains(described[permission]),
        reason: '$permission n’est pas annoncée',
      );
    }
  });

  test('la politique ne promet pas une permission unique', () {
    // Le micro s'est ajouté à Internet quand la dictée est arrivée : la phrase
    // d'origine est restée juste assez longtemps pour devenir fausse.
    expect(policy, isNot(contains('seule permission')));
    expect(policy, contains('Permissions'));
  });

  test('les permissions écartées par la politique restent absentes', () {
    for (final refused in <String>[
      'CAMERA',
      'READ_EXTERNAL_STORAGE',
      'WRITE_EXTERNAL_STORAGE',
      'READ_MEDIA_IMAGES',
      'ACCESS_FINE_LOCATION',
      'ACCESS_COARSE_LOCATION',
      'READ_CONTACTS',
    ]) {
      expect(
        declared,
        isNot(contains(refused)),
        reason:
            '$refused est déclarée alors que la politique affirme le '
            'contraire',
      );
    }
  });
}
