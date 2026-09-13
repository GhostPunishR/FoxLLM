// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/llm/backend/end_of_turn.dart';

/// Fait passer [chunks] dans le filtre et rend le texte finalement affiché.
String run(List<String> chunks) {
  final filter = EndOfTurnFilter();
  final buffer = StringBuffer();
  for (final chunk in chunks) {
    buffer.write(filter.add(chunk));
    if (filter.isFinished) {
      return buffer.toString();
    }
  }
  buffer.write(filter.flush());
  return buffer.toString();
}

void main() {
  group('texte ordinaire', () {
    test('passe entier', () {
      expect(
        run(<String>['Bonjour', ' !', ' Comment ça va ?']),
        'Bonjour ! Comment ça va ?',
      );
    });

    test('ne retient rien quand rien n’amorce un marqueur', () {
      final filter = EndOfTurnFilter();
      expect(filter.add('Voici une réponse'), 'Voici une réponse');
    });

    test('laisse passer un chevron isolé', () {
      expect(
        run(<String>['if (a < b) {', ' return a; }']),
        'if (a < b) { return a; }',
      );
    });

    test('laisse passer du code HTML', () {
      expect(run(<String>['<div>', 'salut', '</div>']), '<div>salut</div>');
    });
  });

  group('fin de tour', () {
    test('coupe au marqueur ChatML', () {
      expect(
        run(<String>['Bonjour.', '<|im_end|>', '\nautre chose']),
        'Bonjour.',
      );
    });

    test('coupe quand le modèle reprend la parole de l’utilisateur', () {
      // Exactement ce que produisait le prompt inventé : le modèle enchaînait
      // sur le tour suivant au lieu de s'arrêter.
      expect(
        run(<String>['Oui, je comprends.\n', '<|system|>', '\ncan we learn?']),
        'Oui, je comprends.\n',
      );
    });

    test('coupe sur un marqueur Llama 3', () {
      expect(run(<String>['Réponse courte.', '<|eot_id|>']), 'Réponse courte.');
    });

    test('coupe sur une balise de fin de séquence', () {
      expect(run(<String>['Terminé.', '</s>', ' suite ignorée']), 'Terminé.');
    });

    test('reconnaît un marqueur arrivé en plusieurs morceaux', () {
      expect(
        run(<String>['Fini.', '<|im', '_end', '|>', ' jamais vu']),
        'Fini.',
      );
    });

    test('reconnaît un marqueur découpé jeton par jeton', () {
      expect(
        run(<String>[
          'A',
          '<',
          '|',
          'a',
          's',
          's',
          'i',
          's',
          't',
          'a',
          'n',
          't',
          '|',
          '>',
          'B',
        ]),
        'A',
      );
    });

    test('garde le texte qui précède le marqueur dans le même morceau', () {
      expect(run(<String>['Voilà.<|im_end|>reste']), 'Voilà.');
    });

    test('ne rend plus rien après la coupure', () {
      final filter = EndOfTurnFilter();
      filter.add('Fini.<|im_end|>');
      expect(filter.isFinished, isTrue);
      expect(filter.add('encore du texte'), isEmpty);
      expect(filter.flush(), isEmpty);
    });
  });

  test('le texte retenu ressort si le flux s’arrête sans marqueur', () {
    // « <|im » n'est pas un marqueur : ce qui a été retenu doit réapparaître
    // plutôt que d'être perdu.
    expect(run(<String>['Réponse tronquée <|im']), 'Réponse tronquée <|im');
  });
}
