// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/llm/model/citation.dart';

void main() {
  group('Citation', () {
    test('l’hôte sert d’intitulé quand le titre manque', () {
      const bare = Citation(url: 'https://www.exemple.fr/article/1');
      expect(bare.host, 'exemple.fr');
      expect(bare.label, 'exemple.fr');

      const titled = Citation(url: 'https://exemple.fr/a', title: 'Un article');
      expect(titled.label, 'Un article');
    });

    test('une entrée illisible ne casse pas la conversation', () {
      expect(Citation.fromJson(null), isNull);
      expect(
        Citation.fromJson(<String, Object?>{'title': 'sans adresse'}),
        isNull,
      );
      expect(Citation.fromJson(<String, Object?>{'url': '   '}), isNull);

      final citation = Citation.fromJson(<String, Object?>{
        'url': 'https://exemple.fr',
        'title': 'Titre',
      });
      expect(citation?.url, 'https://exemple.fr');
      expect(citation?.title, 'Titre');
    });

    test('l’aller-retour JSON conserve la source', () {
      const citation = Citation(url: 'https://exemple.fr/a', title: 'A');
      expect(Citation.fromJson(citation.toJson()), citation);
    });
  });

  group('addCitation', () {
    test('une même adresse n’apparaît qu’une fois', () {
      final citations = <Citation>[];
      addCitation(citations, const Citation(url: 'https://a.fr', title: 'A'));
      addCitation(citations, const Citation(url: 'https://b.fr', title: 'B'));
      addCitation(citations, const Citation(url: 'https://a.fr', title: 'A'));

      expect(citations.map((citation) => citation.url), <String>[
        'https://a.fr',
        'https://b.fr',
      ], reason: 'l’ordre d’apparition est conservé');
    });

    test('un titre arrivé plus tard complète une entrée nue', () {
      final citations = <Citation>[];
      addCitation(citations, const Citation(url: 'https://a.fr'));
      addCitation(citations, const Citation(url: 'https://a.fr', title: 'A'));

      expect(citations.single.title, 'A');
    });

    test('une adresse vide est ignorée', () {
      final citations = <Citation>[];
      addCitation(citations, const Citation(url: '   '));
      expect(citations, isEmpty);
    });
  });
}
