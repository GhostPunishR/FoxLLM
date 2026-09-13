// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/llm/personal_api_settings.dart';
import 'package:foxllm/core/llm/personal_api_settings_provider.dart';
import 'package:foxllm/core/llm/provider_config.dart';
import 'package:foxllm/core/security/api_key_store.dart';
import 'package:foxllm/features/settings/personal_api_screen.dart';

void main() {
  testWidgets('affiche les réglages enregistrés au premier rendu', (
    tester,
  ) async {
    await _useTallSurface(tester);
    final navigator = GlobalKey<NavigatorState>();

    await tester.pumpWidget(_hostApp(_FakeSettingsStore(), navigator));
    await _openScreen(tester);

    expect(find.text('Ton fournisseur, ta clé, ton modèle'), findsOneWidget);
    expect(find.text('gpt-exemple'), findsWidgets);
    expect(find.text('Supprimer la clé API'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('revenir en arrière pendant un test de connexion ne rappelle '
      'pas setState', (tester) async {
    // `_save()` rend ses réglages même si l'écran a été quitté entre-temps.
    // Sans garde `mounted`, `_testConnection()` enchaînait sur un `setState()`
    // après `dispose()` et le framework levait une exception.
    await _useTallSurface(tester);
    final navigator = GlobalKey<NavigatorState>();
    final saveGate = Completer<void>();

    await tester.pumpWidget(
      _hostApp(_FakeSettingsStore(saveGate: saveGate), navigator),
    );
    await _openScreen(tester);

    await tester.tap(find.text('Tester la connexion'));
    await tester.pump();

    // L'utilisateur ferme l'écran alors que l'enregistrement est encore en vol.
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(PersonalApiScreen), findsNothing);

    saveGate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

Future<void> _useTallSurface(WidgetTester tester) async {
  // La page est une ListView : sur une surface de test standard, les boutons du
  // bas ne seraient ni construits ni atteignables.
  await tester.binding.setSurfaceSize(const Size(600, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _openScreen(WidgetTester tester) async {
  await tester.tap(find.text('Ouvrir'));
  await tester.pumpAndSettle();
}

Widget _hostApp(_FakeSettingsStore store, GlobalKey<NavigatorState> navigator) {
  return ProviderScope(
    overrides: [
      personalApiSettingsStoreProvider.overrideWithValue(store),
      apiKeyStoreProvider.overrideWithValue(_FakeApiKeyStore()),
    ],
    child: MaterialApp(
      navigatorKey: navigator,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const PersonalApiScreen(),
              ),
            ),
            child: const Text('Ouvrir'),
          ),
        ),
      ),
    ),
  );
}

class _FakeSettingsStore implements PersonalApiSettingsStore {
  _FakeSettingsStore({this.saveGate});

  final Completer<void>? saveGate;

  PersonalApiSettings settings = const PersonalApiSettings(
    providerId: 'openai',
    model: 'gpt-exemple',
    hasApiKey: true,
  );

  @override
  Future<PersonalApiSettings> load({required ApiKeyStore keyStore}) async =>
      settings;

  @override
  Future<void> save(PersonalApiSettings next) async {
    await saveGate?.future;
    settings = next;
  }
}

class _FakeApiKeyStore extends ApiKeyStore {
  @override
  Future<String?> read({
    required String providerId,
    required ApiKeyPersistence persistence,
  }) async {
    return 'secret';
  }

  @override
  Future<void> save({
    required String providerId,
    required String apiKey,
    required ApiKeyPersistence persistence,
  }) async {}

  @override
  Future<void> delete(String providerId) async {}
}
