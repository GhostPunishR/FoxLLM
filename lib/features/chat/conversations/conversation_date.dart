// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

/// Datation des conversations dans le menu latéral.
///
/// Tout se compte en jours de calendrier, de minuit à minuit, et jamais en
/// tranches de vingt-quatre heures : une conversation d'hier soir appartient à
/// « Hier » dès qu'il est minuit, pas le lendemain à la même heure.
library;

/// Tranche d'ancienneté sous laquelle une conversation est rangée.
enum ConversationAge {
  today('Aujourd’hui'),
  yesterday('Hier'),
  week('7 derniers jours'),
  month('30 derniers jours'),
  older('Plus tôt');

  const ConversationAge(this.label);

  /// Intitulé de la section, tel qu'il s'affiche.
  final String label;
}

/// Tranche à laquelle appartient une conversation mise à jour le [updatedAt].
///
/// Une date postérieure à [now] retombe sur [ConversationAge.today] : cela
/// n'arrive qu'avec une horloge reculée, et mieux vaut ranger la conversation
/// au plus près que d'annoncer un âge négatif.
ConversationAge conversationAge(DateTime updatedAt, DateTime now) {
  final days = dayDifference(updatedAt, now);
  if (days <= 0) {
    return ConversationAge.today;
  }
  if (days == 1) {
    return ConversationAge.yesterday;
  }
  if (days < 7) {
    return ConversationAge.week;
  }
  if (days < 30) {
    return ConversationAge.month;
  }
  return ConversationAge.older;
}

/// Date portée par une conversation, sans répéter le titre de sa section.
///
/// Aujourd'hui et hier, l'heure situe la conversation dans la journée ; au
/// delà, c'est le jour qui compte. L'année n'apparaît que si ce n'est pas
/// l'année en cours, où elle n'apprendrait rien.
String conversationStamp(DateTime updatedAt, DateTime now) {
  final days = dayDifference(updatedAt, now);
  if (days <= 1) {
    return '${_twoDigits(updatedAt.hour)}:${_twoDigits(updatedAt.minute)}';
  }
  if (updatedAt.year == now.year) {
    return '${updatedAt.day} ${_frenchMonths[updatedAt.month - 1]}';
  }
  return '${_twoDigits(updatedAt.day)}/${_twoDigits(updatedAt.month)}/'
      '${_twoDigits(updatedAt.year % 100)}';
}

/// Jours de calendrier écoulés entre [from] et [to], heures ignorées.
int dayDifference(DateTime from, DateTime to) {
  final fromDay = DateTime(from.year, from.month, from.day);
  final toDay = DateTime(to.year, to.month, to.day);
  return toDay.difference(fromDay).inDays;
}

/// Prochain minuit après [now] : le moment où les tranches changent de sens.
DateTime nextMidnight(DateTime now) =>
    DateTime(now.year, now.month, now.day + 1);

String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// Mois abrégés à la française, sans dépendance de localisation.
const _frenchMonths = <String>[
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];
