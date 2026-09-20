// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/diagnostics/first_error.dart';

void main() {
  setUp(forgetFirstError);
  tearDown(forgetFirstError);

  test('la première erreur est gardée, les suivantes ne l’écrasent pas', () {
    // Tout l'objet du relevé : une construction qui échoue entraîne le
    // démontage de son entourage, qui échoue à son tour. Sans ce garde, c'est
    // la seconde erreur qui reste à l'écran, et elle ne dit rien de la cause.
    final previous = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previous);

    installFirstErrorScreen();
    FlutterError.onError!(
      FlutterErrorDetails(exception: Exception('la cause')),
    );
    FlutterError.onError!(
      FlutterErrorDetails(exception: Exception('la conséquence')),
    );

    expect(firstError?.exceptionAsString(), contains('la cause'));
  });

  testWidgets('l’écran donne le message et la pile', (tester) async {
    late final StackTrace stack;
    try {
      throw StateError('le moteur a refusé');
    } catch (error, trace) {
      stack = trace;
    }

    await tester.pumpWidget(
      FirstErrorScreen(
        details: FlutterErrorDetails(
          exception: StateError('le moteur a refusé'),
          stack: stack,
          library: 'la construction du chat',
        ),
      ),
    );

    expect(find.text('Première erreur'), findsOneWidget);
    expect(find.textContaining('le moteur a refusé'), findsOneWidget);
    expect(find.textContaining('pendant : la construction'), findsOneWidget);
    expect(find.text('Pile d’appels'), findsOneWidget);
  });

  testWidgets('l’écran tient sans thème, sans police et sans image', (
    tester,
  ) async {
    // Il doit s'afficher quand tout le reste a échoué, y compris la palette :
    // le poser hors de toute application est la seule façon de le prouver.
    await tester.pumpWidget(
      FirstErrorScreen(
        details: FlutterErrorDetails(exception: Exception('rien ne va')),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('rien ne va'), findsOneWidget);
  });

  testWidgets('une erreur sans pile s’affiche quand même', (tester) async {
    await tester.pumpWidget(
      FirstErrorScreen(
        details: FlutterErrorDetails(exception: Exception('sans trace')),
      ),
    );

    expect(find.textContaining('sans trace'), findsOneWidget);
    expect(find.text('Pile d’appels'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
