import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxgpt/features/settings/about_screen.dart';
import 'package:foxgpt/features/settings/legal_documents.dart';
import 'package:foxgpt/features/settings/settings_screen.dart';

void main() {
  testWidgets('les Paramètres ouvrent À propos et n’affichent plus le pied de '
      'page', (tester) async {
    await _useTallSurface(tester);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pump();

    // Le libellé « FoxGPT » ne subsiste que comme titre de section.
    expect(find.text('FoxGPT'), findsOneWidget);
    expect(find.text('À propos'), findsOneWidget);

    await tester.tap(find.text('À propos'));
    await tester.pumpAndSettle();

    expect(find.byType(AboutScreen), findsOneWidget);
    expect(find.text('Conditions d’utilisation'), findsOneWidget);
    expect(find.text('Politique de confidentialité'), findsOneWidget);
    expect(find.text('Version $foxGptVersion'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chaque document légal est consultable', (tester) async {
    await _useTallSurface(tester);

    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pump();

    for (final document in <LegalDocument>[
      termsOfUseDocument,
      privacyPolicyDocument,
    ]) {
      await tester.tap(find.text(document.title));
      await tester.pumpAndSettle();

      expect(find.byType(LegalDocumentScreen), findsOneWidget);
      expect(
        find.text('Dernière mise à jour : ${document.updatedAt}'),
        findsOneWidget,
      );
      // Chaque section et son premier paragraphe sont rendus.
      for (final section in document.sections) {
        expect(find.text(section.title), findsOneWidget);
      }
      expect(
        find.text(document.sections.first.paragraphs.first),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  test('les documents ont un contenu non vide', () {
    for (final document in <LegalDocument>[
      termsOfUseDocument,
      privacyPolicyDocument,
    ]) {
      expect(document.title, isNotEmpty);
      expect(document.updatedAt, isNotEmpty);
      expect(document.sections, isNotEmpty);
      for (final section in document.sections) {
        expect(section.title, isNotEmpty);
        expect(section.paragraphs, isNotEmpty);
        for (final paragraph in section.paragraphs) {
          expect(paragraph.trim(), isNotEmpty);
        }
      }
    }
  });

  test('foxGptVersion reste en phase avec pubspec.yaml', () {
    // L'écran À propos affiche cette constante : sans ce garde, elle pourrait
    // diverger silencieusement de la version réellement publiée.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull, reason: 'version absente de pubspec.yaml');
    expect(foxGptVersion, match!.group(1));
  });
}

Future<void> _useTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(600, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}
