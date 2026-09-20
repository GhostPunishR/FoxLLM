// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// L'écran de chat décide sans cesse si une opération asynchrone a encore le
/// droit d'écrire : la génération est-elle toujours la bonne, le fil est-il
/// toujours celui qui est ouvert ?
///
/// Deux règles, et non une. Ce qui écrit dans une conversation par son
/// identifiant se contente de l'époque, car une conversation quittée reste
/// modifiable. Ce qui touche au fil affiché exige les deux, sous peine de
/// réécrire la conversation de quelqu'un d'autre.
///
/// Ces contrôles portent sur la source : ils n'empêchent pas d'écrire une
/// mauvaise règle, ils empêchent d'en recopier une de travers, ce qui a
/// produit trois des défauts les plus coûteux du dépôt.
void main() {
  final screen = File('lib/features/chat/chat_screen.dart').readAsStringSync();

  test('la règle d’identité n’est écrite qu’une fois', () {
    final comparisons = RegExp(
      r'[!=]= _generationEpoch|_generationEpoch [!=]=',
    ).allMatches(screen).length;

    expect(
      comparisons,
      1,
      reason:
          'l’époque est comparée $comparisons fois : la règle doit vivre dans '
          '`_isCurrentGeneration`, que `_isCurrentThread` resserre',
    );
  });

  test('les deux règles existent et se distinguent', () {
    expect(screen, contains('bool _isCurrentGeneration(int generationEpoch)'));
    expect(
      screen,
      contains(
        'bool _isCurrentThread(int generationEpoch, int? conversationId)',
      ),
    );
    // La stricte s'appuie sur la souple : deux règles indépendantes
    // finiraient par diverger.
    expect(screen, contains('_isCurrentGeneration(generationEpoch) &&'));
  });

  test('l’identité du fil affiché se lit par sa règle', () {
    // `_activeConversationId` sert aussi à désigner le fil courant hors de
    // toute question d'identité. Seules les comparaisons mêlées à une époque
    // sont visées : elles doivent passer par `_isCurrentThread`.
    //
    // La définition de la règle est elle-même un tel voisinage : elle est
    // retirée avant de compter, sinon le contrôle se signalerait lui-même.
    final elsewhere = screen.replaceAll(
      RegExp(
        r'bool _isCurrentThread\(int generationEpoch, int\? conversationId\)'
        r'[^;]+;',
      ),
      '',
    );
    final mixed = RegExp(
      r'generationEpoch[^;]{0,80}_activeConversationId',
    ).allMatches(elsewhere).length;

    expect(
      mixed,
      0,
      reason:
          'une comparaison d’époque voisine d’une comparaison de conversation '
          'est une copie de `_isCurrentThread` écrite à la main',
    );
  });
}
