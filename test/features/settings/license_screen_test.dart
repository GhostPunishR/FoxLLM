// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxgpt/core/theme/fox_theme.dart';
import 'package:foxgpt/features/settings/about_screen.dart';
import 'package:foxgpt/features/settings/license_screen.dart';

void main() {
  group('fichier LICENSE', () {
    test('porte bien le texte officiel de l’AGPL v3', () {
      final license = File('LICENSE').readAsStringSync();

      expect(license, contains('GNU AFFERO GENERAL PUBLIC LICENSE'));
      expect(license, contains('Version 3, 19 November 2007'));
      expect(license, contains('TERMS AND CONDITIONS'));
      expect(license, contains('END OF TERMS AND CONDITIONS'));
      // La clause 13 est ce qui distingue l'AGPL de la GPL.
      expect(
        license,
        contains('13. Remote Network Interaction'),
        reason: 'la clause réseau manquerait : ce ne serait pas l’AGPL',
      );
      expect(license, contains('15. Disclaimer of Warranty.'));
      expect(license.length, greaterThan(30000));
    });

    test('est déclaré comme ressource de l’application', () {
      // Sans cette déclaration, l'écran Licence n'aurait rien à afficher.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('\n    - LICENSE'));
    });

    testWidgets('est réellement embarqué avec l’application', (tester) async {
      // La déclaration seule ne prouve rien : cette lecture passe par le même
      // chemin que l'écran Licence, hors horloge simulée.
      String? text;
      await tester.runAsync(() async => text = await loadLicenseText());

      expect(text, contains('GNU AFFERO GENERAL PUBLIC LICENSE'));
    });
  });

  group('écran Licence', () {
    testWidgets('affiche le texte intégral', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final license = File('LICENSE').readAsStringSync();
      await tester.pumpWidget(
        MaterialApp(
          theme: FoxTheme.light.themeData,
          home: LicenseScreen(loader: () async => license),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Licence'), findsOneWidget);
      expect(
        find.textContaining('GNU Affero General Public License'),
        findsWidgets,
      );
      expect(
        find.textContaining('GNU AFFERO GENERAL PUBLIC LICENSE'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('À propos', () {
    testWidgets('propose la licence et les licences tierces', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: AboutScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Licence'), findsOneWidget);
      expect(find.text('GNU Affero General Public License v3'), findsOneWidget);
      expect(find.text('Licences tierces'), findsOneWidget);
    });

    testWidgets('l’entrée Licence ouvre le texte officiel', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: AboutScreen())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Licence'));
      await tester.pumpAndSettle();

      // Le contenu vient d'une ressource que le banc de test ne lit pas sous
      // horloge simulée ; l'écran ouvert suffit ici, son texte est vérifié
      // au-dessus avec une lecture directe du fichier.
      expect(find.byType(LicenseScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
