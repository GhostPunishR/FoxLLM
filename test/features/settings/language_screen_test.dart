// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/l10n/fox_language.dart';
import 'package:foxllm/core/l10n/fox_language_labels.dart';
import 'package:foxllm/core/l10n/language_provider.dart';
import 'package:foxllm/core/theme/fox_theme.dart';
import 'package:foxllm/features/settings/appearance_screen.dart';
import 'package:foxllm/features/settings/language_screen.dart';
import 'package:foxllm/l10n/app_localizations.dart';

import '../../support/localized_app.dart';

/// Les traductions sans arbre de widgets, pour nommer ce que l'écran affiche.
final l10n = lookupAppLocalizations(const Locale('fr'));

Future<void> _pump(WidgetTester tester, Widget home) async {
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        foxLanguageStoreProvider.overrideWithValue(_MemoryLanguageStore()),
      ],
      child: localizedApp(theme: FoxTheme.light.themeData, home: home),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('l’écran propose les trois langues et coche celle en place', (
    tester,
  ) async {
    await _pump(tester, const LanguageScreen());

    for (final language in FoxLanguage.values) {
      expect(find.text(language.label(l10n)), findsOneWidget);
    }
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(
      find.byIcon(Icons.radio_button_unchecked),
      findsNWidgets(FoxLanguage.values.length - 1),
    );
  });

  testWidgets('choisir une langue l’enregistre et la coche', (tester) async {
    final store = _MemoryLanguageStore();
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [foxLanguageStoreProvider.overrideWithValue(store)],
        child: localizedApp(
          theme: FoxTheme.light.themeData,
          home: const LanguageScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text(FoxLanguage.english.label(l10n)));
    await tester.pumpAndSettle();

    expect(store.saved, FoxLanguage.english);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LanguageScreen)),
    );
    expect(container.read(foxLanguageProvider), FoxLanguage.english);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la langue a quitté l’écran Apparence', (tester) async {
    // Elle s'y trouvait au bas d'une liste de couleurs : c'est précisément ce
    // que ce déplacement corrige. Sans ce contrôle, la remettre passerait.
    await _pump(tester, const AppearanceScreen());

    expect(find.text(l10n.languageIntro), findsNothing);
    for (final language in FoxLanguage.values) {
      expect(find.text(language.description(l10n)), findsNothing);
    }
  });
}

/// Stockage en mémoire : le banc ne touche pas au trousseau de l'appareil.
class _MemoryLanguageStore implements FoxLanguageStore {
  FoxLanguage? saved;

  @override
  Future<FoxLanguage> load() async => saved ?? FoxLanguage.system;

  @override
  Future<void> save(FoxLanguage language) async => saved = language;
}
