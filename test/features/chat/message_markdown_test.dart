// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxgpt/features/chat/message_markdown.dart';

void main() {
  group('parseMessageSegments', () {
    test('un message sans bloc reste intact', () {
      const content = 'Bonjour !\nComment ça va ?';
      expect(parseMessageSegments(content), <MessageSegment>[
        const MessageText(content),
      ]);
    });

    test('isole un bloc de code et son langage', () {
      final segments = parseMessageSegments(
        'Voici un exemple :\n'
        '```dart\n'
        'void main() {}\n'
        '```\n'
        'Et voilà.',
      );

      expect(segments, <MessageSegment>[
        const MessageText('Voici un exemple :'),
        const MessageCode(code: 'void main() {}', language: 'dart'),
        const MessageText('Et voilà.'),
      ]);
    });

    test('un bloc sans langage annoncé reste un bloc', () {
      final segments = parseMessageSegments('```\nls -la\n```');
      expect(segments, <MessageSegment>[const MessageCode(code: 'ls -la')]);
    });

    test('un bloc encore ouvert est marqué incomplet', () {
      // Cas du streaming : la clôture fermante n'est pas encore arrivée.
      final segments = parseMessageSegments('```js\nconst a = 1;');
      expect(segments, <MessageSegment>[
        const MessageCode(
          code: 'const a = 1;',
          language: 'js',
          isComplete: false,
        ),
      ]);
    });

    test('une clôture ouvrante seule n’affiche pas de bloc vide', () {
      expect(parseMessageSegments('Voici :\n```'), <MessageSegment>[
        const MessageText('Voici :'),
      ]);
    });

    test('gère plusieurs blocs successifs', () {
      final segments = parseMessageSegments(
        '```py\na = 1\n```\nPuis :\n```py\nb = 2\n```',
      );
      expect(segments, hasLength(3));
      expect(segments.whereType<MessageCode>().map((c) => c.code), <String>[
        'a = 1',
        'b = 2',
      ]);
    });

    test('trois accents graves au fil d’une phrase ne coupent rien', () {
      const content = 'Entoure le code de ``` pour le mettre en bloc.';
      expect(parseMessageSegments(content), <MessageSegment>[
        const MessageText(content),
      ]);
    });

    test('les retours à la ligne internes du code sont conservés', () {
      final segments = parseMessageSegments('```\nun\n\ndeux\n```');
      expect((segments.single as MessageCode).code, 'un\n\ndeux');
    });
  });

  group('buildInlineSpans', () {
    test('met en gras le texte entouré de doubles astérisques', () {
      final spans = buildInlineSpans(
        'La **réponse** est là.',
        codeStyle: const TextStyle(),
      );

      expect(spans.map((s) => (s as TextSpan).text), <String>[
        'La ',
        'réponse',
        ' est là.',
      ]);
      // Les astérisques disparaissent au profit du gras qu'elles demandaient.
      expect((spans[1] as TextSpan).style?.fontWeight, FontWeight.w700);
      expect((spans[0] as TextSpan).style?.fontWeight, isNull);
    });

    test('met en italique un seul astérisque', () {
      final spans = buildInlineSpans(
        'Un mot *souligné* ici.',
        codeStyle: const TextStyle(),
      );

      expect((spans[1] as TextSpan).text, 'souligné');
      expect((spans[1] as TextSpan).style?.fontStyle, FontStyle.italic);
      expect((spans[1] as TextSpan).style?.fontWeight, isNull);
    });

    test('combine gras et italique imbriqués', () {
      final spans = buildInlineSpans(
        '**très *fort* ici**',
        codeStyle: const TextStyle(),
      );

      final inner = spans.cast<TextSpan>().firstWhere(
        (span) => span.text == 'fort',
      );
      expect(inner.style?.fontWeight, FontWeight.w700);
      expect(inner.style?.fontStyle, FontStyle.italic);
    });

    test('trois astérisques donnent gras et italique', () {
      final spans = buildInlineSpans(
        '***très fort***',
        codeStyle: const TextStyle(),
      );

      expect(spans.single.toPlainText(), 'très fort');
      final style = (spans.single as TextSpan).style;
      expect(style?.fontWeight, FontWeight.w700);
      expect(style?.fontStyle, FontStyle.italic);
    });

    test('une rangée d’astérisques reste telle quelle', () {
      const text = '5 étoiles ***** pour toi';
      final spans = buildInlineSpans(text, codeStyle: const TextStyle());
      expect(spans.map((s) => s.toPlainText()).join(), text);
    });

    test('une multiplication n’est pas une mise en valeur', () {
      const text = 'Calcule 2 * 3 * 4 pour voir.';
      final spans = buildInlineSpans(text, codeStyle: const TextStyle());

      expect(spans.single.toPlainText(), text);
      expect((spans.single as TextSpan).style?.fontStyle, isNull);
    });

    test('des astérisques non refermées restent du texte', () {
      const text = 'Une **promesse non tenue';
      final spans = buildInlineSpans(text, codeStyle: const TextStyle());

      expect(spans.map((s) => s.toPlainText()).join(), text);
    });

    test('la mise en valeur ne traverse pas un paragraphe', () {
      const text = 'Début *ouvert\n\nSuite* fermée';
      final spans = buildInlineSpans(text, codeStyle: const TextStyle());

      expect(spans.map((s) => s.toPlainText()).join(), text);
    });

    test('les tirets bas ne déclenchent rien', () {
      // Sinon `__init__` ou `nom_de_variable` perdraient leurs tirets.
      const text = 'Appelle __init__ sur nom_de_variable.';
      final spans = buildInlineSpans(text, codeStyle: const TextStyle());

      expect(spans.single.toPlainText(), text);
    });

    test('le code en ligne garde ses astérisques', () {
      final spans = buildInlineSpans(
        'Écris `a ** b` ainsi.',
        codeStyle: const TextStyle(fontFamily: 'monospace'),
      );

      expect((spans[1] as TextSpan).text, 'a ** b');
      expect((spans[1] as TextSpan).style?.fontFamily, 'monospace');
    });

    test('met en valeur le code en ligne sans ses accents graves', () {
      final spans = buildInlineSpans(
        'Appelle `ping()` ensuite.',
        codeStyle: const TextStyle(fontFamily: 'monospace'),
      );

      expect(spans.map((s) => (s as TextSpan).text), <String>[
        'Appelle ',
        'ping()',
        ' ensuite.',
      ]);
      expect((spans[1] as TextSpan).style?.fontFamily, 'monospace');
    });

    test('laisse le texte sans accent grave en un seul fragment', () {
      final spans = buildInlineSpans(
        'Rien à signaler',
        codeStyle: const TextStyle(),
      );
      expect(spans, hasLength(1));
    });
  });

  group('parseTextBlocks', () {
    test('reconnaît les titres et leur niveau', () {
      expect(parseTextBlocks('# Grand\n### Petit'), <MessageBlock>[
        const HeadingBlock(text: 'Grand', level: 1),
        const HeadingBlock(text: 'Petit', level: 3),
      ]);
    });

    test('un dièse sans espace n’est pas un titre', () {
      expect(parseTextBlocks('#1 du classement'), <MessageBlock>[
        const ParagraphBlock('#1 du classement'),
      ]);
    });

    test('reconnaît les puces, quel que soit le marqueur', () {
      expect(parseTextBlocks('- un\n* deux\n+ trois'), <MessageBlock>[
        const ListItemBlock(text: 'un', bullet: '•'),
        const ListItemBlock(text: 'deux', bullet: '•'),
        const ListItemBlock(text: 'trois', bullet: '•'),
      ]);
    });

    test('garde les numéros d’une liste ordonnée', () {
      expect(parseTextBlocks('1. un\n2) deux'), <MessageBlock>[
        const ListItemBlock(text: 'un', bullet: '1.'),
        const ListItemBlock(text: 'deux', bullet: '2.'),
      ]);
    });

    test('déduit l’imbrication de l’indentation', () {
      final blocks = parseTextBlocks('- parent\n  - enfant\n    - petit');
      expect(blocks.cast<ListItemBlock>().map((b) => b.depth), <int>[0, 1, 2]);
    });

    test('un astérisque collé au mot reste une mise en valeur', () {
      expect(parseTextBlocks('*italique* en début de ligne'), <MessageBlock>[
        const ParagraphBlock('*italique* en début de ligne'),
      ]);
    });

    test('reconnaît un trait de séparation', () {
      expect(parseTextBlocks('avant\n\n---\n\naprès'), <MessageBlock>[
        const ParagraphBlock('avant'),
        const DividerBlock(),
        const ParagraphBlock('après'),
      ]);
    });

    test('les lignes vides séparent les paragraphes', () {
      expect(parseTextBlocks('un\ndeux\n\ntrois'), <MessageBlock>[
        const ParagraphBlock('un\ndeux'),
        const ParagraphBlock('trois'),
      ]);
    });

    test('un texte ordinaire tient en un seul paragraphe', () {
      expect(parseTextBlocks('Bonjour tout le monde'), <MessageBlock>[
        const ParagraphBlock('Bonjour tout le monde'),
      ]);
    });
  });

  group('liens', () {
    test('affiche le libellé et retire la syntaxe', () {
      final spans = buildInlineSpans(
        'Voir [le site](https://example.com) pour la suite.',
        codeStyle: const TextStyle(),
        linkStyle: const TextStyle(decoration: TextDecoration.underline),
      );

      expect(
        spans.map((s) => s.toPlainText()).join(),
        'Voir le site pour la suite.',
      );
      expect(
        (spans[1] as TextSpan).style?.decoration,
        TextDecoration.underline,
      );
    });

    test('l’appui remonte l’adresse', () {
      Uri? opened;
      final recognizers = <GestureRecognizer>[];
      final spans = buildInlineSpans(
        '[doc](https://example.com/a)',
        codeStyle: const TextStyle(),
        onLinkTap: (url) => opened = url,
        recognizers: recognizers,
      );
      addTearDown(() {
        for (final recognizer in recognizers) {
          recognizer.dispose();
        }
      });

      expect(recognizers, hasLength(1));
      final recognizer =
          (spans.single as TextSpan).recognizer! as TapGestureRecognizer;
      recognizer.onTap!();
      expect(opened, Uri.parse('https://example.com/a'));
    });

    test('un schéma autre que http reste du texte', () {
      // L'application refuserait de l'ouvrir : autant l'afficher tel quel.
      const text = 'Essaie [ceci](javascript:alert(1)) pour voir.';
      final spans = buildInlineSpans(text, codeStyle: const TextStyle());
      expect(spans.map((s) => s.toPlainText()).join(), text);
    });

    test('une forme incomplète reste du texte', () {
      const text = 'Un [crochet] seul et [autre](sans-schema).';
      final spans = buildInlineSpans(text, codeStyle: const TextStyle());
      expect(spans.map((s) => s.toPlainText()).join(), text);
    });
  });

  group('MessageMarkdown', () {
    testWidgets('affiche le code en bloc et masque les délimiteurs', (
      tester,
    ) async {
      await _pump(tester, 'Voici :\n```dart\nvoid main() {}\n```');

      expect(find.byType(CodeBlock), findsOneWidget);
      expect(find.text('dart'), findsOneWidget);
      expect(find.text('void main() {}'), findsOneWidget);
      expect(find.textContaining('```'), findsNothing);
    });

    testWidgets('le bouton copier place le code dans le presse-papiers', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await _pump(tester, '```sh\necho ok\n```');
      await tester.tap(find.text('Copier'));
      await tester.pump();

      expect(copied, 'echo ok');
      // Retour visuel immédiat, puis retour au libellé d'origine.
      expect(find.text('Copié'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Copier'), findsOneWidget);
    });

    testWidgets('n’affiche plus les astérisques du gras', (tester) async {
      await _pump(tester, 'Voici la **réponse** attendue.');

      expect(find.textContaining('**'), findsNothing);
      expect(find.text('Voici la réponse attendue.'), findsOneWidget);
    });

    testWidgets('rend titres, listes et liens sans leurs marques', (
      tester,
    ) async {
      await _pump(
        tester,
        '## Trois étapes\n'
        '\n'
        '1. Ouvrir [le site](https://example.com)\n'
        '2. Lire la **doc**\n'
        '\n'
        '---\n'
        '\n'
        'Voilà.',
      );

      expect(find.textContaining('##'), findsNothing);
      expect(find.textContaining('](http'), findsNothing);
      expect(find.text('Trois étapes'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('Ouvrir le site'), findsOneWidget);
      expect(find.text('Lire la doc'), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('l’appui sur un lien l’ouvre à l’extérieur', (tester) async {
      Uri? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MessageMarkdown(
                content: 'Voir [le site](https://example.com).',
                textStyle: const TextStyle(fontSize: 16),
                openLink: (url) async {
                  opened = url;
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tapOnText(find.textRange.ofSubstring('le site'));
      await tester.pumpAndSettle();

      expect(opened, Uri.parse('https://example.com'));
    });

    testWidgets('un lien qui ne s’ouvre pas le dit', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MessageMarkdown(
                content: '[lien](https://example.com)',
                textStyle: const TextStyle(fontSize: 16),
                openLink: (url) async => false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tapOnText(find.textRange.ofSubstring('lien'));
      await tester.pumpAndSettle();

      expect(find.text('Lien impossible à ouvrir.'), findsOneWidget);
    });

    testWidgets('un message sans code reste un simple texte', (tester) async {
      await _pump(tester, 'Bonjour tout le monde');

      expect(find.byType(CodeBlock), findsNothing);
      expect(find.text('Bonjour tout le monde'), findsOneWidget);
    });
  });
}

Future<void> _pump(WidgetTester tester, String content) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: MessageMarkdown(
            content: content,
            textStyle: const TextStyle(fontSize: 16),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
