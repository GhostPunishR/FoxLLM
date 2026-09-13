// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxgpt/features/chat/chat_screen.dart';
import 'package:foxgpt/features/chat/text_attachment.dart';

void main() {
  group('decodeTextAttachment', () {
    test('accepte un fichier texte', () {
      final attachment = decodeTextAttachment(
        'note.txt',
        Uint8List.fromList(utf8.encode('Bonjour')),
      );
      expect(attachment.name, 'note.txt');
      expect(attachment.text, 'Bonjour');
    });

    test('refuse un fichier trop volumineux', () {
      expect(
        () => decodeTextAttachment(
          'gros.txt',
          Uint8List(maxAttachmentBytes + 1)..fillRange(0, 10, 65),
        ),
        throwsA(
          isA<AttachmentException>().having(
            (e) => e.message,
            'message',
            contains('trop volumineux'),
          ),
        ),
      );
    });

    test('refuse un binaire repéré par ses octets nuls', () {
      expect(
        () => decodeTextAttachment(
          'image.png',
          Uint8List.fromList(<int>[0x89, 0x50, 0x00, 0x0D]),
        ),
        throwsA(isA<AttachmentException>()),
      );
    });

    test('refuse un contenu qui n’est pas de l’UTF-8', () {
      expect(
        () => decodeTextAttachment(
          'latin.txt',
          Uint8List.fromList(<int>[0xC3, 0x28, 0xA9]),
        ),
        throwsA(isA<AttachmentException>()),
      );
    });

    test('refuse un fichier vide', () {
      expect(
        () => decodeTextAttachment(
          'vide.txt',
          Uint8List.fromList(utf8.encode('   \n')),
        ),
        throwsA(
          isA<AttachmentException>().having(
            (e) => e.message,
            'message',
            contains('vide'),
          ),
        ),
      );
    });
  });

  group('formatAttachment', () {
    test('annonce le langage déduit de l’extension', () {
      final block = formatAttachment(
        const TextAttachment(name: 'main.dart', text: 'void main() {}\n'),
      );
      expect(
        block,
        'Fichier joint : main.dart\n```dart\nvoid main() {}\n```\n',
      );
    });

    test('laisse la clôture sans langage si l’extension est inconnue', () {
      final block = formatAttachment(
        const TextAttachment(name: 'notes', text: 'texte'),
      );
      expect(block, 'Fichier joint : notes\n```\ntexte\n```\n');
    });
  });

  group('menu « + » du composer', () {
    testWidgets('propose fichier, photos et caméra, sans modèles locaux', (
      tester,
    ) async {
      await _pumpChat(tester, _FakePicker());
      await _openAddMenu(tester);

      expect(find.text('Joindre un fichier'), findsOneWidget);
      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('Caméra'), findsOneWidget);
      // Le chargement d'un GGUF n'a rien à faire ici : il reste dans
      // Paramètres → Modèles locaux.
      expect(find.text('Modèles locaux'), findsNothing);
    });

    testWidgets('joindre un fichier l’ajoute au message en cours', (
      tester,
    ) async {
      await _pumpChat(
        tester,
        _FakePicker(
          attachment: const TextAttachment(
            name: 'main.dart',
            text: 'void main() {}',
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Explique ce code');
      await tester.pump();
      await _openAddMenu(tester);
      await tester.tap(find.text('Joindre un fichier'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(
        field.controller!.text,
        'Explique ce code\n'
        'Fichier joint : main.dart\n'
        '```dart\n'
        'void main() {}\n'
        '```\n',
      );
      expect(find.textContaining('main.dart'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un fichier refusé explique pourquoi sans rien insérer', (
      tester,
    ) async {
      await _pumpChat(
        tester,
        _FakePicker(error: const AttachmentException('Ce fichier est vide.')),
      );

      await _openAddMenu(tester);
      await tester.tap(find.text('Joindre un fichier'));
      await tester.pumpAndSettle();

      expect(find.text('Ce fichier est vide.'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('annuler le sélecteur laisse le brouillon intact', (
      tester,
    ) async {
      await _pumpChat(tester, _FakePicker());

      await tester.enterText(find.byType(TextField), 'Brouillon');
      await tester.pump();
      await _openAddMenu(tester);
      await tester.tap(find.text('Joindre un fichier'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Brouillon');
    });
  });
}

Future<void> _pumpChat(WidgetTester tester, AttachmentPicker picker) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [attachmentPickerProvider.overrideWithValue(picker)],
      child: const MaterialApp(home: ChatScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openAddMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Ajouter'));
  await tester.pumpAndSettle();
}

class _FakePicker extends AttachmentPicker {
  _FakePicker({this.attachment, this.error});

  /// `null` simule une annulation du sélecteur système.
  final TextAttachment? attachment;
  final AttachmentException? error;

  @override
  Future<TextAttachment?> pickTextFile() async {
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return attachment;
  }
}
