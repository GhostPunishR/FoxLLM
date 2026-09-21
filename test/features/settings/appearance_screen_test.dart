// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/theme/fox_palette.dart';
import 'package:foxllm/core/theme/fox_theme.dart';
import 'package:foxllm/core/theme/system_appearance.dart';
import 'package:foxllm/core/theme/theme_provider.dart';
import 'package:foxllm/features/settings/appearance_screen.dart';
import 'package:foxllm/core/theme/fox_theme_labels.dart';
import 'package:foxllm/l10n/app_localizations.dart';
import 'package:foxllm/main.dart';

import '../../support/localized_app.dart';

/// Les libellés se traduisent : ils se lisent donc dans les traductions, et
/// non plus sur l'énumération. `lookupAppLocalizations` les rend sans arbre de
/// widgets, ce dont ces contrôles ont besoin.
final l10n = lookupAppLocalizations(const Locale('fr'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FoxTheme', () {
    test('chaque déclinaison expose sa palette dans le ThemeData', () {
      for (final theme in FoxTheme.values) {
        final data = theme.themeData;
        expect(data.brightness, theme.brightness);
        expect(data.extension<FoxPalette>(), theme.palette);
        expect(data.scaffoldBackgroundColor, theme.palette.background);
        expect(theme.label(l10n), isNotEmpty);
        expect(theme.description(l10n), isNotEmpty);
      }
    });

    test('les deux déclinaisons sont bien distinctes', () {
      expect(
        FoxTheme.dark.palette.background,
        isNot(FoxTheme.light.palette.background),
      );
      expect(FoxTheme.dark.brightness, Brightness.dark);
      expect(FoxTheme.light.brightness, Brightness.light);
    });

    test('les deux palettes gardent un texte lisible sur le fond', () {
      for (final theme in FoxTheme.values) {
        final palette = theme.palette;
        final ratio = _contrast(palette.textPrimary, palette.background);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '${theme.name} : contraste du texte principal insuffisant',
        );
        // 4,5 et non 3 : ces deux teintes servent à des textes de douze ou
        // treize points, la date d'une conversation, une aide de réglage, la
        // mention de copyright. Le seuil de 3 ne vaut que pour du texte large,
        // que l'application n'utilise nulle part pour ces rôles.
        expect(
          _contrast(palette.textSecondary, palette.background),
          greaterThanOrEqualTo(4.5),
          reason: '${theme.name} : contraste du texte secondaire insuffisant',
        );
        expect(
          _contrast(palette.textTertiary, palette.background),
          greaterThanOrEqualTo(4.5),
          reason: '${theme.name} : contraste du texte tertiaire insuffisant',
        );
        expect(
          _contrast(palette.onAccent, palette.accent),
          greaterThanOrEqualTo(3.0),
          reason: '${theme.name} : contraste sur l’orange insuffisant',
        );
      }
    });
  });

  group('déclinaison par défaut', () {
    test('la déclinaison claire ouvre la liste et s’applique sans réglage', () {
      // L'ordre de l'énumération est celui de l'écran Apparence.
      expect(FoxTheme.values.first, FoxTheme.light);
      expect(FoxTheme.values.last, FoxTheme.dark);

      final container = ProviderContainer(
        overrides: [
          foxThemeStoreProvider.overrideWithValue(_MemoryThemeStore()),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(foxThemeProvider), FoxTheme.light);
    });

    testWidgets('l’écran affiche la déclinaison claire en premier', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            foxThemeStoreProvider.overrideWithValue(_MemoryThemeStore()),
          ],
          child: localizedApp(
            theme: FoxTheme.light.themeData,
            home: const AppearanceScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getTopLeft(find.text(l10n.themeLightLabel)).dy,
        lessThan(tester.getTopLeft(find.text(l10n.themeDarkLabel)).dy),
      );
    });
  });

  group('fenêtre de lancement Android', () {
    test('le choix est déclaré au système, qui teinte le splash', () async {
      final modes = _recordNightModes();
      final container = ProviderContainer(
        overrides: [
          foxThemeStoreProvider.overrideWithValue(_MemoryThemeStore()),
        ],
      );
      addTearDown(container.dispose);

      await container.read(foxThemeProvider.notifier).select(FoxTheme.dark);
      await Future<void>.delayed(Duration.zero);
      expect(modes.last, isTrue);

      await container.read(foxThemeProvider.notifier).select(FoxTheme.light);
      await Future<void>.delayed(Duration.zero);
      expect(modes.last, isFalse);
    });

    test('la préférence relue au lancement est redite au système', () async {
      final modes = _recordNightModes();
      final container = ProviderContainer(
        overrides: [
          foxThemeStoreProvider.overrideWithValue(
            _MemoryThemeStore(saved: FoxTheme.dark),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(foxThemeProvider);
      await Future<void>.delayed(Duration.zero);

      expect(modes, <bool>[true]);
    });

    test(
      'un canal absent ne fait pas échouer le changement de thème',
      () async {
        // Hors Android, aucun gestionnaire n'est branché sur le canal.
        final container = ProviderContainer(
          overrides: [
            foxThemeStoreProvider.overrideWithValue(_MemoryThemeStore()),
          ],
        );
        addTearDown(container.dispose);

        await container.read(foxThemeProvider.notifier).select(FoxTheme.dark);
        expect(container.read(foxThemeProvider), FoxTheme.dark);
      },
    );
  });

  testWidgets('choisir une déclinaison change le thème de l’application', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = _MemoryThemeStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [foxThemeStoreProvider.overrideWithValue(store)],
        child: const FoxLlmApp(),
      ),
    );
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    expect(container.read(foxThemeProvider), FoxTheme.light);

    await container.read(foxThemeProvider.notifier).select(FoxTheme.dark);
    await tester.pumpAndSettle();

    expect(container.read(foxThemeProvider), FoxTheme.dark);
    expect(store.saved, FoxTheme.dark);

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.theme!.brightness, Brightness.dark);
    expect(materialApp.theme!.extension<FoxPalette>(), FoxPalette.dark);
  });

  testWidgets('l’écran Apparence coche la déclinaison active', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          foxThemeStoreProvider.overrideWithValue(_MemoryThemeStore()),
        ],
        child: localizedApp(
          theme: FoxTheme.light.themeData,
          home: const AppearanceScreen(),
        ),
      ),
    );
    await tester.pump();

    for (final theme in FoxTheme.values) {
      expect(find.text(theme.label(l10n)), findsOneWidget);
    }
    // L'écran ne porte plus que les déclinaisons : la langue a le sien.
    // Une seule rangée est cochée, et le reste ne l'est pas.
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(
      find.byIcon(Icons.radio_button_unchecked),
      findsNWidgets(FoxTheme.values.length - 1),
    );

    await tester.tap(find.text(l10n.themeDarkLabel));
    await tester.pumpAndSettle();

    // Toujours une seule coche : la déclinaison a changé, pas leur nombre.
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'un choix fait pendant la lecture du stockage n’est pas écrasé',
    () async {
      // Le stockage répond après coup : sans garde, la préférence relue
      // reviendrait par-dessus la déclinaison que l'utilisateur vient de
      // choisir.
      final store = _MemoryThemeStore(saved: FoxTheme.light, delayed: true);
      final container = ProviderContainer(
        overrides: [foxThemeStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      container.read(foxThemeProvider);
      await container.read(foxThemeProvider.notifier).select(FoxTheme.dark);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(container.read(foxThemeProvider), FoxTheme.dark);
    },
  );

  test('le choix enregistré est relu au démarrage', () async {
    final store = _MemoryThemeStore(saved: FoxTheme.dark);
    final container = ProviderContainer(
      overrides: [foxThemeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    // Le thème clair s'applique d'abord, sans attendre le stockage.
    expect(container.read(foxThemeProvider), FoxTheme.light);

    await Future<void>.delayed(Duration.zero);
    expect(container.read(foxThemeProvider), FoxTheme.dark);
  });
}

/// Branche un faux canal natif et retourne les modes reçus, dans l'ordre.
List<bool> _recordNightModes() {
  final modes = <bool>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemAppearance.channel, (call) async {
    if (call.method == 'setDarkMode') {
      modes.add(call.arguments as bool);
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemAppearance.channel, null),
  );
  return modes;
}

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

class _MemoryThemeStore implements FoxThemeStore {
  _MemoryThemeStore({this.saved, this.delayed = false});

  FoxTheme? saved;

  /// Simule un stockage lent, qui répond après le premier frame.
  final bool delayed;

  @override
  Future<FoxTheme> load() async {
    if (delayed) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return saved ?? FoxTheme.light;
  }

  @override
  Future<void> save(FoxTheme theme) async => saved = theme;
}
