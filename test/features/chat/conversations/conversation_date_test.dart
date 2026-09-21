// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/features/chat/conversations/conversation_date.dart';
import 'package:foxllm/l10n/app_localizations.dart';

/// Les intitulés se traduisent : ils se lisent dans les traductions, comme le
/// tiroir les lit.
final _l10n = lookupAppLocalizations(const Locale('fr'));

void main() {
  group('tranches', () {
    // Un mardi, en milieu de journée.
    final now = DateTime(2026, 9, 15, 14, 30);

    test('le jour de calendrier décide, pas les vingt-quatre heures', () {
      // Dix minutes avant minuit, relues dix minutes après : la conversation
      // a beau avoir vingt minutes, elle n'est plus d'aujourd'hui.
      final justBeforeMidnight = DateTime(2026, 9, 14, 23, 50);
      final justAfterMidnight = DateTime(2026, 9, 15, 0, 10);

      expect(
        conversationAge(justBeforeMidnight, justBeforeMidnight),
        ConversationAge.today,
      );
      expect(
        conversationAge(justBeforeMidnight, justAfterMidnight),
        ConversationAge.yesterday,
      );
    });

    test(
      'une conversation de la veille n’est jamais annoncée à sept jours',
      () {
        // Le défaut d'origine : tout ce qui n'était plus d'aujourd'hui tombait
        // dans une seule section, intitulée « 7 jours ».
        final age = conversationAge(DateTime(2026, 9, 14, 23, 50), now);
        expect(age, ConversationAge.yesterday);
        expect(age.label(_l10n), 'Hier');
      },
    );

    test('chaque tranche couvre ce qu’elle annonce', () {
      final cases = <int, ConversationAge>{
        0: ConversationAge.today,
        1: ConversationAge.yesterday,
        2: ConversationAge.week,
        6: ConversationAge.week,
        7: ConversationAge.month,
        29: ConversationAge.month,
        30: ConversationAge.older,
        365: ConversationAge.older,
      };
      cases.forEach((days, expected) {
        final updatedAt = DateTime(2026, 9, 15 - days, 8);
        expect(
          conversationAge(updatedAt, now),
          expected,
          reason: '$days jour(s) devrait tomber dans ${expected.name}',
        );
      });
    });

    test('une horloge reculée ne produit pas d’âge négatif', () {
      expect(
        conversationAge(DateTime(2026, 9, 17, 9), now),
        ConversationAge.today,
      );
    });

    test('les intitulés disent la durée réelle', () {
      expect(ConversationAge.values.map((age) => age.label(_l10n)), <String>[
        'Aujourd’hui',
        'Hier',
        '7 derniers jours',
        '30 derniers jours',
        'Plus tôt',
      ]);
    });
  });

  group('date affichée', () {
    final now = DateTime(2026, 9, 15, 14, 30);

    test('aujourd’hui et hier donnent l’heure', () {
      expect(conversationStamp(DateTime(2026, 9, 15, 9, 5), now), '09:05');
      expect(conversationStamp(DateTime(2026, 9, 14, 23, 50), now), '23:50');
    });

    test('dans l’année, le jour et le mois suffisent', () {
      expect(conversationStamp(DateTime(2026, 9, 2, 8), now), '2 sept.');
      expect(conversationStamp(DateTime(2026, 1, 31, 8), now), '31 janv.');
      expect(conversationStamp(DateTime(2026, 8, 12, 8), now), '12 août');
    });

    test('une autre année porte la sienne', () {
      expect(conversationStamp(DateTime(2025, 12, 24, 8), now), '24/12/25');
      expect(conversationStamp(DateTime(2020, 3, 5, 9, 30), now), '05/03/20');
    });

    test('les douze mois ont un nom', () {
      for (var month = 1; month <= 12; month++) {
        final stamp = conversationStamp(
          DateTime(2026, month, 1, 8),
          DateTime(2026, 12, 31, 23),
        );
        expect(stamp, startsWith('1 '));
        expect(stamp.split(' ').last, isNotEmpty);
      }
    });
  });

  group('prochain minuit', () {
    test('tombe au début du jour suivant', () {
      expect(
        nextMidnight(DateTime(2026, 9, 15, 14, 30)),
        DateTime(2026, 9, 16),
      );
    });

    test('franchit les fins de mois et d’année', () {
      expect(nextMidnight(DateTime(2026, 9, 30, 23, 59)), DateTime(2026, 10));
      expect(nextMidnight(DateTime(2026, 12, 31, 23, 59)), DateTime(2027));
      // Année bissextile : le 29 février existe.
      expect(nextMidnight(DateTime(2028, 2, 28, 12)), DateTime(2028, 2, 29));
    });

    test('est toujours dans le futur', () {
      for (final hour in <int>[0, 1, 12, 23]) {
        final now = DateTime(2026, 9, 15, hour, 30);
        expect(nextMidnight(now).isAfter(now), isTrue);
      }
    });
  });
}
