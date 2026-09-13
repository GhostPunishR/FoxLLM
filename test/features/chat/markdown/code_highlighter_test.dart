// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/theme/fox_palette.dart';
import 'package:foxllm/core/theme/fox_theme.dart';
import 'package:foxllm/features/chat/markdown/code_highlighter.dart';
import 'package:foxllm/features/chat/markdown/message_markdown.dart';

void main() {
  group('highlightCode', () {
    test('distingue mots-clés, chaînes, nombres et appels', () {
      final tokens = highlightCode(
        "final name = greet('Renard', 42);",
        language: 'dart',
      );

      expect(_typeOf(tokens, 'final'), CodeTokenType.keyword);
      expect(_typeOf(tokens, "'Renard'"), CodeTokenType.string);
      expect(_typeOf(tokens, '42'), CodeTokenType.number);
      expect(_typeOf(tokens, 'greet'), CodeTokenType.call);
      // `name` n'est ni un mot-clé ni un appel : il reste du texte courant.
      expect(tokens.where((t) => t.type == CodeTokenType.call), hasLength(1));
    });

    test('le texte reconstitué est identique au code d’origine', () {
      const code = '''
// Additionne deux entiers.
int add(int a, int b) {
  return a + b; /* évident */
}
''';
      final tokens = highlightCode(code, language: 'dart');
      expect(tokens.map((t) => t.text).join(), code);
    });

    test('reconnaît le commentaire de ligne du langage annoncé', () {
      final dart = highlightCode('// note\nvar x = 1;', language: 'dart');
      expect(dart.first, const CodeToken('// note', CodeTokenType.comment));

      final python = highlightCode('# note\nx = 1', language: 'python');
      expect(python.first, const CodeToken('# note', CodeTokenType.comment));

      // Le dièse n'ouvre pas un commentaire en Dart.
      final hashInDart = highlightCode('var x = 1; # pas un commentaire');
      expect(
        hashInDart.where((t) => t.type == CodeTokenType.comment),
        isNotEmpty,
        reason: 'le repli générique accepte les deux syntaxes',
      );
      final strictDart = highlightCode(
        'var x = 1; # pas un commentaire',
        language: 'dart',
      );
      expect(strictDart.where((t) => t.type == CodeTokenType.comment), isEmpty);
    });

    test('un commentaire multiligne est pris en entier', () {
      final tokens = highlightCode('/* deux\n   lignes */\nx', language: 'js');
      expect(tokens.first.type, CodeTokenType.comment);
      expect(tokens.first.text, '/* deux\n   lignes */');
    });

    test('une apostrophe isolée ne colore pas la suite du fichier', () {
      // Sans garde, le `'` de « l'API » ouvrirait une chaîne jusqu'au bout.
      final tokens = highlightCode(
        "// l'API\nfinal a = 1;\nfinal b = 2;",
        language: 'dart',
      );
      expect(_typeOf(tokens, 'final'), CodeTokenType.keyword);
      expect(_typeOf(tokens, '1'), CodeTokenType.number);
      expect(_typeOf(tokens, '2'), CodeTokenType.number);
    });

    test('une chaîne non refermée s’arrête en fin de ligne', () {
      final tokens = highlightCode('x = "oubli\ny = 2', language: 'python');
      expect(_typeOf(tokens, '"oubli'), CodeTokenType.string);
      expect(_typeOf(tokens, '2'), CodeTokenType.number);
    });

    test('les échappements ne ferment pas la chaîne', () {
      final tokens = highlightCode(r'''print("a\"b", 7)''', language: 'python');
      expect(_typeOf(tokens, r'"a\"b"'), CodeTokenType.string);
      expect(_typeOf(tokens, '7'), CodeTokenType.number);
    });

    test('un langage inconnu reste lisible sans colorer à tort', () {
      final tokens = highlightCode(
        'ceci est du texte ordinaire',
        language: 'klingon',
      );
      expect(tokens.single.type, CodeTokenType.plain);
    });

    test('les mots-clés SQL et son commentaire à double tiret', () {
      final tokens = highlightCode(
        '-- total\nselect id from users',
        language: 'sql',
      );
      expect(tokens.first.type, CodeTokenType.comment);
      expect(_typeOf(tokens, 'select'), CodeTokenType.keyword);
      expect(_typeOf(tokens, 'from'), CodeTokenType.keyword);
    });

    test('un code vide ne produit aucun fragment', () {
      expect(highlightCode(''), isEmpty);
    });
  });

  group('codeSpans', () {
    test('chaque fragment reçoit la couleur de son rôle', () {
      final spans = codeSpans(
        "const a = 'x'; // note",
        language: 'dart',
        palette: FoxPalette.dark,
      );

      Color? colorOf(String text) => spans
          .cast<TextSpan>()
          .firstWhere((span) => span.text == text)
          .style
          ?.color;

      expect(colorOf('const'), FoxPalette.dark.codeKeyword);
      expect(colorOf("'x'"), FoxPalette.dark.codeString);
      expect(colorOf('// note'), FoxPalette.dark.codeComment);
    });
  });

  group('lisibilité des couleurs de code', () {
    test('chaque rôle reste lisible sur le fond des blocs', () {
      for (final theme in FoxTheme.values) {
        final p = theme.palette;
        final roles = <String, Color>{
          'commentaire': p.codeComment,
          'mot-clé': p.codeKeyword,
          'chaîne': p.codeString,
          'nombre': p.codeNumber,
          'appel': p.codeCall,
          'texte courant': p.textPrimary,
        };
        roles.forEach((name, color) {
          expect(
            _contrast(color, p.surfaceInput),
            greaterThanOrEqualTo(4.5),
            reason: '${theme.label} : contraste insuffisant pour $name',
          );
        });
      }
    });

    test('les rôles se distinguent les uns des autres', () {
      for (final theme in FoxTheme.values) {
        final p = theme.palette;
        final colors = <Color>{
          p.codeComment,
          p.codeKeyword,
          p.codeString,
          p.codeNumber,
          p.codeCall,
          p.textPrimary,
        };
        expect(
          colors,
          hasLength(6),
          reason: '${theme.label} : rôles confondus',
        );
      }
    });
  });
}

CodeTokenType _typeOf(List<CodeToken> tokens, String text) =>
    tokens.firstWhere((token) => token.text == text).type;

/// Rapport de contraste WCAG 2.1 entre deux couleurs opaques.
double _contrast(Color a, Color b) {
  double luminance(Color c) {
    double channel(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
    return 0.2126 * channel(c.r) +
        0.7152 * channel(c.g) +
        0.0722 * channel(c.b);
  }

  final first = luminance(a);
  final second = luminance(b);
  final lighter = math.max(first, second);
  final darker = math.min(first, second);
  return (lighter + 0.05) / (darker + 0.05);
}
