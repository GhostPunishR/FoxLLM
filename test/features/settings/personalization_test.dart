// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxgpt/core/llm/personalization.dart';
import 'package:foxgpt/core/theme/fox_theme.dart';
import 'package:foxgpt/features/settings/personalization_screen.dart';
import 'package:foxgpt/features/settings/settings_screen.dart';

void main() {
  group('PersonalizationController', () {
    test(
      'relit les instructions enregistrées après le premier frame',
      () async {
        final store = _MemoryStore(stored: 'Réponds en breton.');
        final container = ProviderContainer(
          overrides: [personalizationStoreProvider.overrideWithValue(store)],
        );
        addTearDown(container.dispose);

        // Rien n'attend le stockage : l'écran s'affiche d'abord sans consigne.
        expect(container.read(personalizationProvider), isEmpty);

        expect(
          await container.read(personalizationProvider.notifier).resolved(),
          'Réponds en breton.',
        );
        expect(container.read(personalizationProvider), 'Réponds en breton.');
      },
    );

    test('enregistre en retirant les espaces superflus', () async {
      final store = _MemoryStore();
      final container = ProviderContainer(
        overrides: [personalizationStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      await container
          .read(personalizationProvider.notifier)
          .save('  Sois concis.  ');

      expect(container.read(personalizationProvider), 'Sois concis.');
      expect(store.stored, 'Sois concis.');
    });

    test('des instructions vides effacent la préférence', () async {
      final store = _MemoryStore(stored: 'Ancienne consigne');
      final container = ProviderContainer(
        overrides: [personalizationStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      await container.read(personalizationProvider.notifier).save('   ');

      expect(container.read(personalizationProvider), isEmpty);
      expect(store.stored, isEmpty);
    });

    test('tronque au-delà de la limite', () async {
      final store = _MemoryStore();
      final container = ProviderContainer(
        overrides: [personalizationStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      await container
          .read(personalizationProvider.notifier)
          .save('a' * (maxInstructionsLength + 50));

      expect(
        container.read(personalizationProvider).length,
        maxInstructionsLength,
      );
    });

    test('un stockage illisible laisse l’IA sans consigne', () async {
      final container = ProviderContainer(
        overrides: [
          personalizationStoreProvider.overrideWithValue(_BrokenStore()),
        ],
      );
      addTearDown(container.dispose);

      expect(
        await container.read(personalizationProvider.notifier).resolved(),
        isEmpty,
      );
    });
  });

  group('écran Personnalisation', () {
    testWidgets('remplace Confidentialité dans les paramètres', (tester) async {
      await _pump(tester, const SettingsScreen(), _MemoryStore());

      expect(find.text('Personnalisation'), findsOneWidget);
      expect(find.text('Confidentialité'), findsNothing);

      await tester.tap(find.text('Personnalisation'));
      await tester.pumpAndSettle();

      expect(find.byType(PersonalizationScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('enregistre les instructions saisies', (tester) async {
      final store = _MemoryStore();
      await _pump(tester, const PersonalizationScreen(), store);

      await tester.enterText(
        find.byType(TextField),
        'Réponds toujours en français, en trois phrases maximum.',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(
        store.stored,
        'Réponds toujours en français, en trois phrases maximum.',
      );
      expect(find.text('Instructions enregistrées.'), findsOneWidget);
    });

    testWidgets('un modèle prêt à l’emploi remplit le champ', (tester) async {
      final store = _MemoryStore();
      await _pump(tester, const PersonalizationScreen(), store);

      final preset = personalizationPresets.first;
      await tester.tap(find.text(preset.label));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, preset.instructions);
    });

    testWidgets('le champ reprend les instructions déjà enregistrées', (
      tester,
    ) async {
      await _pump(
        tester,
        const PersonalizationScreen(),
        _MemoryStore(stored: 'Consigne existante'),
      );
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Consigne existante');
    });

    testWidgets('effacer vide le champ et la préférence', (tester) async {
      final store = _MemoryStore(stored: 'À retirer');
      await _pump(tester, const PersonalizationScreen(), store);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Effacer'));
      await tester.pumpAndSettle();

      expect(store.stored, isEmpty);
      expect(find.text('Instructions effacées.'), findsOneWidget);
    });
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen,
  PersonalizationStore store,
) async {
  await tester.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [personalizationStoreProvider.overrideWithValue(store)],
      child: MaterialApp(theme: FoxTheme.dark.themeData, home: screen),
    ),
  );
  await tester.pump();
}

class _MemoryStore extends PersonalizationStore {
  _MemoryStore({this.stored = ''});

  String stored;

  @override
  Future<String> load() async => stored;

  @override
  Future<void> save(String instructions) async {
    stored = instructions.trim();
  }
}

class _BrokenStore extends PersonalizationStore {
  @override
  Future<String> load() async => throw StateError('stockage indisponible');
}
