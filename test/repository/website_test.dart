// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/app_info.dart';
import 'package:foxllm/features/settings/about/legal_documents.dart';

/// Le site publié depuis `docs/` par GitHub Pages.
///
/// Un seul fichier : les textes légaux y sont des sections plutôt que des
/// pages, la feuille de style et le script y sont écrits à même la page. Ce
/// qui liait ces textes à ceux de l'application n'a pas changé pour autant,
/// seul l'endroit où les chercher a bougé.
const _sitePage = 'docs/index.html';
const _pages = <String>[_sitePage];

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
  test('le site existe avec son logo', () {
    // Le logo reste un fichier : c'est une image, pas du code, et l'aperçu
    // des réseaux sociaux a besoin d'une adresse qu'il puisse aller chercher.
    for (final asset in <String>[..._pages, 'docs/fox_logo.png']) {
      expect(File(asset).existsSync(), isTrue, reason: '$asset manquant');
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
    final page = File(_sitePage).readAsStringSync();

    for (final document in <LegalDocument>[
      termsOfUseDocument,
      privacyPolicyDocument,
    ]) {
      expect(page, contains(_escapeHtml(document.title)));
      expect(page, contains(_escapeHtml(document.updatedAt)));

      for (final section in document.sections) {
        // `h3` et non `h2` : le titre du document tient le `h2` de sa bande,
        // et la page n'a qu'un seul `h1`, celui de son en-tête.
        expect(
          page,
          contains('<h3>${_escapeHtml(section.title)}</h3>'),
          reason:
              '${document.title} : section « ${section.title} » absente '
              'du site',
        );
        for (final paragraph in section.paragraphs) {
          expect(
            page,
            contains('<p>${_escapeHtml(paragraph)}</p>'),
            reason:
                '${document.title} : paragraphe manquant sous '
                '« ${section.title} »',
          );
        }
      }
    }
  });

  test('le site tient en un seul fichier', () {
    // Les textes légaux avaient leur page, la mise en forme et la bascule de
    // thème leur fichier. Tout est dans la page. Un fichier revenu à côté
    // rouvrirait la question de savoir lequel fait foi, et une ressource
    // manquante casserait le site sans que rien ne tombe ici.
    const kept = <String>{'index.html', 'fox_logo.png'};
    final strays = Directory('docs')
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .where((name) => !kept.contains(name))
        .toList();

    expect(strays, isEmpty, reason: 'fichiers en trop dans docs/ : $strays');

    final page = File(_sitePage).readAsStringSync();
    expect(
      page,
      contains('<style>'),
      reason: 'la mise en forme a quitté la page',
    );
    expect(
      page,
      contains("root.setAttribute('data-theme', next)"),
      reason: 'la bascule de thème a quitté la page',
    );
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
