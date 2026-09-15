// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

/// Exécute les opérations une par une, dans leur ordre d'arrivée.
///
/// Sert aux services qui pilotent un moteur du système n'ayant qu'un seul
/// état : la synthèse vocale, la reconnaissance vocale. Deux opérations qui
/// s'y chevauchent se marchent dessus, et l'arrêt demandé par la première
/// coupe la seconde.
///
/// Le verrou ne remplace pas la vérification d'actualité : il garantit
/// seulement qu'une opération périmée finit avant que la suivante commence,
/// donc qu'elle ne peut plus la toucher.
class SerialLock {
  Future<void> _tail = Future<void>.value();

  /// Attend la fin de ce qui précède, puis exécute [action].
  ///
  /// L'erreur d'une action ne bloque pas la file : la suivante part quand
  /// même, avec le moteur laissé dans l'état où il est.
  Future<T> run<T>(Future<T> Function() action) async {
    final previous = _tail;
    final mine = Completer<void>();
    _tail = mine.future;
    await previous;
    try {
      return await action();
    } finally {
      mine.complete();
    }
  }
}
