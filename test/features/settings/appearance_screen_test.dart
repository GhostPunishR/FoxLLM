import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxgpt/core/theme/fox_palette.dart';
import 'package:foxgpt/core/theme/fox_theme.dart';
import 'package:foxgpt/core/theme/theme_provider.dart';
import 'package:foxgpt/features/settings/appearance_screen.dart';
import 'package:foxgpt/main.dart';

void main() {
  group('FoxTheme', () {
    test('chaque déclinaison expose sa palette dans le ThemeData', () {
      for (final theme in FoxTheme.values) {
        final data = theme.themeData;
        expect(data.brightness, theme.brightness);
        expect(data.extension<FoxPalette>(), theme.palette);
        expect(data.scaffoldBackgroundColor, theme.palette.background);
        expect(theme.label, isNotEmpty);
        expect(theme.description, isNotEmpty);
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
          reason: '${theme.label} : contraste du texte principal insuffisant',
        );
        expect(
          _contrast(palette.textSecondary, palette.background),
          greaterThanOrEqualTo(3.0),
          reason: '${theme.label} : contraste du texte secondaire insuffisant',
        );
        expect(
          _contrast(palette.onAccent, palette.accent),
          greaterThanOrEqualTo(3.0),
          reason: '${theme.label} : contraste sur l’orange insuffisant',
        );
      }
    });
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
        child: const FoxGptApp(),
      ),
    );
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    expect(container.read(foxThemeProvider), FoxTheme.dark);

    await container.read(foxThemeProvider.notifier).select(FoxTheme.light);
    await tester.pumpAndSettle();

    expect(container.read(foxThemeProvider), FoxTheme.light);
    expect(store.saved, FoxTheme.light);

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.theme!.brightness, Brightness.light);
    expect(materialApp.theme!.extension<FoxPalette>(), FoxPalette.light);
  });

  testWidgets('l’écran Apparence coche la déclinaison active', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          foxThemeStoreProvider.overrideWithValue(_MemoryThemeStore()),
        ],
        child: MaterialApp(
          theme: FoxTheme.dark.themeData,
          home: const AppearanceScreen(),
        ),
      ),
    );
    await tester.pump();

    for (final theme in FoxTheme.values) {
      expect(find.text(theme.label), findsOneWidget);
    }
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(
      find.byIcon(Icons.radio_button_unchecked),
      findsNWidgets(FoxTheme.values.length - 1),
    );

    await tester.tap(find.text(FoxTheme.light.label));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'un choix fait pendant la lecture du stockage n’est pas écrasé',
    () async {
      // Le stockage répond après coup : sans garde, la préférence relue
      // reviendrait par-dessus la déclinaison que l'utilisateur vient de
      // choisir.
      final store = _MemoryThemeStore(saved: FoxTheme.dark, delayed: true);
      final container = ProviderContainer(
        overrides: [foxThemeStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      container.read(foxThemeProvider);
      await container.read(foxThemeProvider.notifier).select(FoxTheme.light);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(container.read(foxThemeProvider), FoxTheme.light);
    },
  );

  test('le choix enregistré est relu au démarrage', () async {
    final store = _MemoryThemeStore(saved: FoxTheme.light);
    final container = ProviderContainer(
      overrides: [foxThemeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    // Le thème sombre s'applique d'abord, sans attendre le stockage.
    expect(container.read(foxThemeProvider), FoxTheme.dark);

    await Future<void>.delayed(Duration.zero);
    expect(container.read(foxThemeProvider), FoxTheme.light);
  });
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
    return saved ?? FoxTheme.dark;
  }

  @override
  Future<void> save(FoxTheme theme) async => saved = theme;
}
