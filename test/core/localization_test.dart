// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:foxllm/core/l10n/fox_language.dart';
import 'package:foxllm/core/l10n/language_provider.dart';
import 'package:foxllm/l10n/app_localizations.dart';
import 'package:foxllm/main.dart';

import '../support/localized_app.dart';

/// Les textes que Flutter fournit lui-même.
///
/// Sans délégation, `MaterialApp` ne dispose que de ses textes anglais : le
/// menu d'un appui long dans un champ de saisie proposait « Cut », « Copy » et
/// « Paste » au milieu d'une application entièrement française. Rien dans
/// `lib/` ne les écrit, donc aucune relecture du code ne pouvait le montrer.
void main() {
  Future<MaterialLocalizations> materialFor(
    WidgetTester tester,
    Locale locale,
  ) async {
    late MaterialLocalizations found;
    await tester.pumpWidget(
      localizedApp(
        locale: locale,
        home: Builder(
          builder: (context) {
            found = MaterialLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return found;
  }

  testWidgets('le menu d’un champ de saisie parle français', (tester) async {
    final material = await materialFor(tester, const Locale('fr'));

    expect(material.pasteButtonLabel, 'Coller');
    expect(material.copyButtonLabel, 'Copier');
    expect(material.selectAllButtonLabel, 'Tout sélectionner');
  });

  testWidgets('et anglais quand l’appareil est anglophone', (tester) async {
    final material = await materialFor(tester, const Locale('en'));

    expect(material.pasteButtonLabel, 'Paste');
  });

  testWidgets('les deux langues sont servies', (tester) async {
    expect(
      AppLocalizations.supportedLocales.map((locale) => locale.languageCode),
      containsAll(<String>['fr', 'en']),
    );
  });

  test('suivre l’appareil ne force aucune langue', () {
    // C'est ce qui permet à une installation sur un téléphone anglophone de
    // parler anglais sans réglage, tout en laissant le choix explicite primer.
    expect(FoxLanguage.system.locale, isNull);
    expect(FoxLanguage.french.locale, const Locale('fr'));
    expect(FoxLanguage.english.locale, const Locale('en'));
  });

  testWidgets('l’application elle-même porte les délégations', (tester) async {
    // Les contrôles ci-dessus passent par l'aide de montage des bancs : ils
    // vérifient les délégations, pas le fait que `FoxLlmApp` les installe.
    // Sans celui-ci, `main.dart` pourrait les perdre sans que rien ne tombe.
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [foxLanguageProvider.overrideWith(_FrenchLanguage.new)],
        child: const FoxLlmApp(),
      ),
    );
    await tester.pump();

    final context = tester.element(find.byType(Navigator).first);
    expect(MaterialLocalizations.of(context).pasteButtonLabel, 'Coller');
  });
}

/// Fige la langue sur le français : le banc ne doit pas dépendre de celle de
/// la machine qui l'exécute, ni d'une lecture asynchrone du stockage.
class _FrenchLanguage extends FoxLanguageController {
  @override
  FoxLanguage build() => FoxLanguage.french;
}
