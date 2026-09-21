// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/l10n/fox_language.dart';
import 'package:foxllm/core/l10n/fox_language_labels.dart';
import 'package:foxllm/core/l10n/language_provider.dart';
import 'package:foxllm/core/storage/last_model_store.dart';
import 'package:foxllm/core/theme/fox_theme.dart';
import 'package:foxllm/features/local_models/local_model_file.dart';
import 'package:foxllm/features/settings/language_screen.dart';
import 'package:foxllm/features/settings/settings_screen.dart';
import 'package:foxllm/l10n/app_localizations.dart';

import '../../support/localized_app.dart';

/// Les traductions sans arbre de widgets, pour nommer ce que l'écran affiche.
final l10n = lookupAppLocalizations(const Locale('fr'));

void main() {
  group('localModelDisplayName', () {
    test('retire le dossier et l’extension', () {
      expect(
        localModelDisplayName('/data/models/Qwen2.5-3B-Instruct-Q4_K_M.gguf'),
        'Qwen2.5-3B-Instruct-Q4_K_M',
      );
    });

    test('accepte un simple nom de fichier', () {
      expect(localModelDisplayName('mistral-7b.GGUF'), 'mistral-7b');
    });

    test('laisse intact un nom sans extension connue', () {
      expect(localModelDisplayName('/tmp/modele.bin'), 'modele.bin');
    });
  });

  group('sous-titre des modèles locaux', () {
    testWidgets('nomme le modèle en place', (tester) async {
      await _pumpSettings(
        tester,
        _FakeLastModelStore('/data/models/Qwen2.5-3B-Instruct-Q4_K_M.gguf'),
      );

      // « llama.cpp » désignait le moteur, pas le modèle : sans intérêt ici.
      expect(find.text('GGUF · llama.cpp'), findsNothing);
      expect(find.text('GGUF · Qwen2.5-3B-Instruct-Q4_K_M'), findsOneWidget);
    });

    testWidgets('signale l’absence de modèle', (tester) async {
      await _pumpSettings(tester, _FakeLastModelStore(null));

      expect(find.text('GGUF · aucun modèle chargé'), findsOneWidget);
    });

    testWidgets('un stockage illisible ne laisse pas l’écran vide', (
      tester,
    ) async {
      await _pumpSettings(tester, _BrokenLastModelStore());

      expect(find.text('Modèles locaux'), findsOneWidget);
      expect(find.text('GGUF · modèle indisponible'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('langue', () {
    testWidgets('la section Application ouvre le choix de langue', (
      tester,
    ) async {
      await _pumpSettings(tester, _FakeLastModelStore(null));

      // Le pavé annonce la langue en place, sans avoir à ouvrir l'écran.
      expect(find.text(l10n.languageTitle), findsOneWidget);
      expect(find.text(FoxLanguage.system.label(l10n)), findsOneWidget);

      await tester.tap(find.text(l10n.languageTitle));
      await tester.pumpAndSettle();

      expect(find.byType(LanguageScreen), findsOneWidget);
    });

    testWidgets('le sous-titre suit le choix enregistré', (tester) async {
      await _pumpSettings(
        tester,
        _FakeLastModelStore(null),
        language: FoxLanguage.english,
      );

      expect(find.text(FoxLanguage.english.label(l10n)), findsOneWidget);
    });
  });
}

Future<void> _pumpSettings(
  WidgetTester tester,
  LastModelStore store, {
  FoxLanguage? language,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        lastModelStoreProvider.overrideWithValue(store),
        foxLanguageStoreProvider.overrideWithValue(
          _MemoryLanguageStore(saved: language),
        ),
      ],
      child: localizedApp(
        theme: FoxTheme.light.themeData,
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Stockage en mémoire : le banc ne touche pas au trousseau de l'appareil.
class _MemoryLanguageStore implements FoxLanguageStore {
  _MemoryLanguageStore({this.saved});

  FoxLanguage? saved;

  @override
  Future<FoxLanguage> load() async => saved ?? FoxLanguage.system;

  @override
  Future<void> save(FoxLanguage language) async => saved = language;
}

class _FakeLastModelStore implements LastModelStore {
  _FakeLastModelStore(this.path);

  String? path;

  @override
  Future<String?> load() async => path;

  @override
  Future<void> save(String value) async => path = value;

  @override
  Future<void> clear() async => path = null;
}

class _BrokenLastModelStore implements LastModelStore {
  @override
  Future<String?> load() async => throw StateError('stockage indisponible');

  @override
  Future<void> save(String value) async {}

  @override
  Future<void> clear() async {}
}
