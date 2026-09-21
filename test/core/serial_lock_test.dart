// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:foxllm/core/async/serial_lock.dart';

/// Le verrou qui sérialise la synthèse vocale et la dictée.
///
/// Trente-deux lignes, mais ce sont elles qui empêchent deux opérations de se
/// marcher dessus sur un moteur du système qui n'a qu'un seul état. Il était
/// couvert indirectement par les bancs de la parole, jamais directement : une
/// régression dedans se serait manifestée comme un défaut de la dictée, loin
/// de sa cause.
void main() {
  test('les actions s’exécutent dans leur ordre d’arrivée', () async {
    final lock = SerialLock();
    final order = <int>[];

    // Lancées ensemble, et volontairement d'autant plus longues qu'elles
    // arrivent tôt : sans verrou, la plus courte finirait la première.
    final futures = <Future<void>>[
      lock.run(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        order.add(1);
      }),
      lock.run(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        order.add(2);
      }),
      lock.run(() async {
        order.add(3);
      }),
    ];
    await Future.wait(futures);

    expect(order, <int>[1, 2, 3]);
  });

  test('aucune action n’en chevauche une autre', () async {
    final lock = SerialLock();
    var running = 0;
    var overlapped = false;

    await Future.wait(<Future<void>>[
      for (var index = 0; index < 8; index++)
        lock.run(() async {
          running++;
          if (running > 1) {
            overlapped = true;
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
          running--;
        }),
    ]);

    expect(overlapped, isFalse);
    expect(running, 0);
  });

  test('une action qui échoue ne bloque pas la file', () async {
    // Le point le plus important : le moteur reste dans l'état où l'échec l'a
    // laissé, mais la file repart. Sans cela, une seule erreur de synthèse
    // vocale rendrait la lecture à voix haute définitivement muette, jusqu'au
    // prochain lancement.
    final lock = SerialLock();
    final done = <String>[];

    await expectLater(
      lock.run<void>(() async => throw StateError('moteur indisponible')),
      throwsStateError,
    );
    await lock.run(() async => done.add('suivante'));

    expect(done, <String>['suivante']);
  });

  test('l’erreur revient à celui qui a demandé l’action', () async {
    final lock = SerialLock();

    await expectLater(
      lock.run<int>(() async => throw const FormatException('cassé')),
      throwsFormatException,
    );
    // Et la file n'en garde pas trace : la suivante réussit normalement.
    expect(await lock.run<int>(() async => 42), 42);
  });

  test('la valeur de l’action est rendue telle quelle', () async {
    final lock = SerialLock();

    expect(await lock.run<String>(() async => 'rendu'), 'rendu');
    expect(await lock.run<int?>(() async => null), isNull);
  });

  test('une action lancée pendant qu’une autre tourne attend son tour', () async {
    final lock = SerialLock();
    final started = Completer<void>();
    final release = Completer<void>();
    var secondStarted = false;

    final first = lock.run(() async {
      started.complete();
      await release.future;
    });
    await started.future;

    final second = lock.run(() async => secondStarted = true);
    // La première n'a pas rendu la main : la seconde ne doit pas avoir démarré.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(secondStarted, isFalse);

    release.complete();
    await Future.wait(<Future<void>>[first, second]);
    expect(secondStarted, isTrue);
  });
}
