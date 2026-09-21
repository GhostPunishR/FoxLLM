// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/features/chat/chat_screen.dart';
import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/features/chat/conversations/conversation_store.dart';
import 'package:foxllm/llm/backend/local_backend_provider.dart';
import 'package:foxllm/llm/backend/local_llm_backend.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm_native/foxllm_native.dart';

import '../../../support/localized_app.dart';

void main() {
  testWidgets('chaque conversation est rangée sous son âge réel', (
    tester,
  ) async {
    await _pumpDrawer(tester, <ChatConversation>[
      _conversation('Ce matin', _daysAgo(0, hour: 0, minute: 1)),
      _conversation('Hier soir', _daysAgo(1, hour: 23, minute: 50)),
      _conversation('Cette semaine', _daysAgo(3)),
      _conversation('Ce mois', _daysAgo(12)),
      _conversation('Il y a longtemps', _daysAgo(200)),
    ]);

    expect(_sections(tester), <String>[
      'Aujourd’hui',
      'Hier',
      '7 derniers jours',
      '30 derniers jours',
      'Plus tôt',
    ]);

    // Ce qui a déclenché la correction : un fil de la veille se retrouvait
    // sous un intitulé annonçant sept jours.
    expect(_sectionOf(tester, 'Hier soir'), 'Hier');
    expect(_sectionOf(tester, 'Ce matin'), 'Aujourd’hui');
    expect(_sectionOf(tester, 'Cette semaine'), '7 derniers jours');
    expect(_sectionOf(tester, 'Ce mois'), '30 derniers jours');
    expect(_sectionOf(tester, 'Il y a longtemps'), 'Plus tôt');
  });

  testWidgets('une tranche vide ne s’affiche pas', (tester) async {
    // Sans conversation d'aujourd'hui, un « Aujourd'hui » vide posé au-dessus
    // des fils d'hier laissait croire qu'ils dataient du jour.
    await _pumpDrawer(tester, <ChatConversation>[
      _conversation('Hier soir', _daysAgo(1, hour: 20)),
    ]);

    expect(_sections(tester), <String>['Hier']);
    expect(find.text('Aujourd’hui'), findsNothing);
    // Le bouton « + » garde son en-tête, qui ne prétend plus dater quoi que
    // ce soit.
    expect(find.text('Chats'), findsOneWidget);
    expect(find.byTooltip('Nouveau chat'), findsWidgets);
  });

  testWidgets('sans conversation, aucune tranche', (tester) async {
    await _pumpDrawer(tester, <ChatConversation>[]);

    expect(_sections(tester), isEmpty);
    expect(find.text('Aucune conversation'), findsOneWidget);
  });

  testWidgets('chaque ligne porte sa date', (tester) async {
    await _pumpDrawer(tester, <ChatConversation>[
      _conversation('Ce matin', _daysAgo(0, hour: 0, minute: 1)),
      _conversation('Hier soir', _daysAgo(1, hour: 23, minute: 50)),
      _conversation('Il y a longtemps', DateTime(2020, 3, 5, 9, 30)),
    ]);

    // L'heure pour les deux derniers jours, la date au-delà : la ligne dit
    // l'âge exact sans dépendre de sa section.
    expect(find.text('00:01'), findsOneWidget);
    expect(find.text('23:50'), findsOneWidget);
    expect(find.text('05/03/20'), findsOneWidget);
  });

  testWidgets('la recherche n’altère pas le classement', (tester) async {
    await _pumpDrawer(tester, <ChatConversation>[
      _conversation('Tarte aux pommes', _daysAgo(0, hour: 0, minute: 1)),
      _conversation('Tarte aux prunes', _daysAgo(1, hour: 20)),
      _conversation('Gratin', _daysAgo(1, hour: 21)),
    ]);

    await tester.enterText(_searchField, 'tarte');
    await tester.pumpAndSettle();

    expect(_sections(tester), <String>['Aujourd’hui', 'Hier']);
    expect(find.text('Gratin'), findsNothing);
    expect(_sectionOf(tester, 'Tarte aux prunes'), 'Hier');
  });
}

/// Champ de recherche du menu latéral, et non celui du composeur : les deux
/// sont montés en même temps quand le menu est ouvert.
final Finder _searchField = find.ancestor(
  of: find.text('Rechercher dans les chats'),
  matching: find.byType(TextField),
);

/// Une date à [days] jours de calendrier en arrière, à l'heure demandée.
///
/// Le calcul part de minuit aujourd'hui, jamais de l'heure courante : un test
/// lancé à 00 h 02 ne doit pas basculer une date dans la veille.
DateTime _daysAgo(int days, {int hour = 12, int minute = 0}) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - days, hour, minute);
}

ChatConversation _conversation(String title, DateTime updatedAt) =>
    ChatConversation(
      id: title.hashCode,
      title: title,
      updatedAt: updatedAt,
      messages: <ChatMessage>[ChatMessage.user(title)],
    );

const _sectionLabels = <String>[
  'Aujourd’hui',
  'Hier',
  '7 derniers jours',
  '30 derniers jours',
  'Plus tôt',
];

/// Intitulés de section présents, de haut en bas.
List<String> _sections(WidgetTester tester) {
  final found = <(double, String)>[];
  for (final label in _sectionLabels) {
    final finder = find.text(label);
    if (finder.evaluate().isEmpty) {
      continue;
    }
    found.add((tester.getTopLeft(finder).dy, label));
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));
  return <String>[for (final entry in found) entry.$2];
}

/// Section sous laquelle [title] s'affiche : le dernier intitulé au-dessus.
String _sectionOf(WidgetTester tester, String title) {
  final top = tester.getTopLeft(find.text(title)).dy;
  String? current;
  for (final label in _sectionLabels) {
    final finder = find.text(label);
    if (finder.evaluate().isEmpty) {
      continue;
    }
    if (tester.getTopLeft(finder).dy < top) {
      current = label;
    }
  }
  return current ?? '(aucune)';
}

Future<void> _pumpDrawer(
  WidgetTester tester,
  List<ChatConversation> conversations,
) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localLlmBackendProvider.overrideWithValue(_IdleBackend()),
        conversationStoreProvider.overrideWithValue(
          _SeededStore(conversations),
        ),
      ],
      child: localizedApp(home: ChatScreen()),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byTooltip('Menu'));
  await tester.pumpAndSettle();
}

class _SeededStore implements ConversationStore {
  _SeededStore(this.seed);

  final List<ChatConversation> seed;

  @override
  Future<List<ChatConversation>> load() async => seed;

  @override
  Future<void> save(List<ChatConversation> conversations) async {}

  @override
  Future<void> clear() async {}
}

class _IdleBackend implements LocalLlmBackend {
  /// Le moteur local dit désormais pourquoi il s’est arrêté ; ce double
  /// n’a rien à écourter.
  @override
  String? get incompleteReason => null;

  @override
  String get id => 'idle';

  @override
  String get displayName => 'Backend de test';

  @override
  String? get loadedModelPath => '/models/test.gguf';

  @override
  Future<String> get nativeVersion async => 'idle/0.0.0';

  @override
  Future<bool> get isModelLoaded async => true;

  @override
  Future<FoxLlmModelInfo?> get modelInfo async => null;

  @override
  Future<FoxLlmGenerationStats?> get lastGenerationStats async => null;

  @override
  Future<void> loadModel(String path) async {}

  @override
  Future<void> unloadModel() async {}

  @override
  Stream<String> generate({
    required List<ChatMessage> messages,
    GenerationSettings settings = const GenerationSettings(),
  }) => Stream<String>.value('ok');

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
