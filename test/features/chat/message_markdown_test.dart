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
