import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxgpt/core/llm/last_model_store.dart';
import 'package:foxgpt/core/theme/fox_theme.dart';
import 'package:foxgpt/features/local_models/local_model_file.dart';
import 'package:foxgpt/features/settings/settings_screen.dart';

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
}

Future<void> _pumpSettings(WidgetTester tester, LastModelStore store) async {
  await tester.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [lastModelStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        theme: FoxTheme.light.themeData,
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
