// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/features/settings/about/legal_documents.dart';

/// Android sauvegarde par défaut le stockage privé d'une application vers le
/// Google Drive de son utilisateur. La politique de confidentialité de FoxLLM
/// affirme que l'historique ne part jamais ailleurs : ces contrôles gardent
/// les deux d'accord, sur le manifeste source.
///
/// Ils ne remplacent pas la vérification du manifeste fusionné, qui demande le
/// SDK Android et se fait en intégration continue.
void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();

  test('la sauvegarde cloud est refusée', () {
    expect(
      manifest,
      contains('android:allowBackup="false"'),
      reason: 'sans cet attribut, Android sauvegarde tout par défaut',
    );
  });

  test('les deux jeux de règles sont déclarés', () {
    // `dataExtractionRules` vaut pour Android 12 et suivants,
    // `fullBackupContent` pour les versions antérieures : déclarer l'un sans
    // l'autre laisse la moitié du parc sans règle.
    expect(manifest, contains('android:dataExtractionRules='));
    expect(manifest, contains('android:fullBackupContent='));
  });

  test('les règles excluent tout, sauvegarde comme transfert', () {
    final rules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();

    for (final section in <String>['cloud-backup', 'device-transfer']) {
      expect(
        rules,
        contains('<$section>'),
        reason: 'une section absente laisse s’appliquer les règles par défaut',
      );
    }
    for (final domain in <String>[
      'root',
      'file',
      'database',
      'sharedpref',
      'external',
    ]) {
      expect(
        rules,
        contains('<exclude domain="$domain" />'),
        reason: '$domain resterait sauvegardé',
      );
    }

    final legacy = File(
      'android/app/src/main/res/xml/backup_rules.xml',
    ).readAsStringSync();
    expect(legacy, contains('<exclude domain="file" path="." />'));
  });

  test('la politique annonce ce que le manifeste applique', () {
    final texts = privacyPolicyDocument.sections
        .expand((section) => <String>[section.title, ...section.paragraphs])
        .join('\n');

    expect(
      texts,
      contains('Sauvegardes Android'),
      reason: 'le refus des sauvegardes doit être annoncé, pas seulement fait',
    );
    // La lecture à voix haute confie le texte au service du système, qui peut
    // le traiter à distance : la politique doit le dire comme pour la dictée.
    expect(texts, contains('Lecture à voix haute'));
    expect(texts, contains('synthèse vocale'));
  });
}
