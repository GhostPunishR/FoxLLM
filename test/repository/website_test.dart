// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/app_info.dart';
import 'package:foxllm/features/settings/about/legal_documents.dart';

/// Pages du site publiées depuis `docs/` par GitHub Pages.
const _pages = <String>[
  'docs/index.html',
  'docs/conditions.html',
  'docs/confidentialite.html',
];

/// Reprend l'échappement appliqué à la génération des pages légales.
String _escapeHtml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#x27;');
}

void main() {
  test('les pages du site existent avec leurs ressources', () {
    for (final page in <String>[
      ..._pages,
      'docs/site.css',
      'docs/theme.js',
      'docs/fox_logo.png',
    ]) {
      expect(File(page).existsSync(), isTrue, reason: '$page manquant');
    }
  });

  test('le site ne renvoie pas vers un fichier absent', () {
    // Un lien interne cassé ne se voit qu'en naviguant : ce garde le signale
    // dès le premier test, y compris après un renommage de fichier.
    final broken = <String>[];
    final pattern = RegExp(r'(?:href|src)="([^"]+)"');

    for (final page in _pages) {
      for (final match in pattern.allMatches(File(page).readAsStringSync())) {
        var target = match.group(1)!;
        if (target.startsWith('http') ||
            target.startsWith('#') ||
            target.startsWith('mailto:')) {
          continue;
        }
        target = target.split('#').first.split('?').first;
        if (target.isEmpty || target == './') {
          target = 'index.html';
        }
        if (!File('docs/$target').existsSync()) {
          broken.add('$page → $target');
        }
      }
    }

    expect(broken, isEmpty, reason: 'liens internes cassés : $broken');
  });

  test('les pages légales reprennent le texte affiché dans l’application', () {
    // Le site sert aussi d'adresse publique pour la politique de
    // confidentialité : les deux versions doivent dire la même chose, mot pour
    // mot, sinon l'une des deux devient fausse sans prévenir.
    final pairs = <String, LegalDocument>{
      'docs/conditions.html': termsOfUseDocument,
      'docs/confidentialite.html': privacyPolicyDocument,
    };

    for (final entry in pairs.entries) {
      final page = File(entry.key).readAsStringSync();
      final document = entry.value;

      expect(page, contains(_escapeHtml(document.title)));
      expect(page, contains(_escapeHtml(document.updatedAt)));

      for (final section in document.sections) {
        expect(
          page,
          contains('<h2>${_escapeHtml(section.title)}</h2>'),
          reason: '${entry.key} : section « ${section.title} » absente',
        );
        for (final paragraph in section.paragraphs) {
          expect(
            page,
            contains('<p>${_escapeHtml(paragraph)}</p>'),
            reason:
                '${entry.key} : paragraphe manquant sous '
                '« ${section.title} »',
          );
        }
      }
    }
  });

  test('le site affiche la version et la licence courantes', () {
    for (final page in _pages) {
      final content = File(page).readAsStringSync();
      expect(
        content,
        contains('FoxLLM $foxLlmVersion'),
        reason: '$page n’annonce pas la version publiée',
      );
      expect(content, contains('AGPL-3.0-only'));
      expect(content, contains(foxLlmSourceUrl));
    }
  });

  test('le dépôt ne renvoie plus vers docs/ARCHITECTURE.md', () {
    // Le document a été remplacé par le site : un lien resté en place
    // conduirait à une page 404 sur GitHub comme sur GitHub Pages.
    expect(File('docs/ARCHITECTURE.md').existsSync(), isFalse);
    expect(
      File('README.md').readAsStringSync(),
      isNot(contains('ARCHITECTURE.md')),
    );
  });
}
