// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/features/chat/chat_screen.dart';
import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/features/chat/conversations/conversation_store.dart';
import 'package:foxllm/llm/backend/local_backend_provider.dart';
import 'package:foxllm/llm/backend/local_llm_backend.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/citation.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm_native/foxllm_native.dart';

import '../../support/localized_app.dart';

void main() {
  group('barre d’actions', () {
    testWidgets('apparaît sous une réponse terminée, pas pendant', (
      tester,
    ) async {
      // Flux tenu ouvert : c'est la seule façon d'observer l'état « en cours
      // de réponse », qu'un flux synchrone traverserait en une frame. Les
      // pompes restent bornées : pendant une génération, rien ne se stabilise.
      final chunks = StreamController<String>();
      final backend = _ScriptedBackend(const <String>[], stream: chunks.stream);
      await _pumpChat(tester, backend);

      await _send(tester, 'Salut');
      chunks.add('Bonjour ');
      await _pumpFrames(tester);

      expect(
        find.byTooltip('Copier'),
        findsNothing,
        reason: 'rien n’est complet à copier, lire ou partager',
      );

      chunks.add('toi !');
      // Fermeture sans `await` : la future ne se résout qu'une fois le flux
      // drainé, ce que seules les pompes suivantes provoquent.
      unawaited(chunks.close());
      await _pumpFrames(tester);

      expect(find.byTooltip('Copier'), findsOneWidget);
      expect(find.byTooltip('Bonne réponse'), findsOneWidget);
      expect(find.byTooltip('Mauvaise réponse'), findsOneWidget);
      expect(find.byTooltip('Lire à voix haute'), findsOneWidget);
      expect(find.byTooltip('Partager'), findsOneWidget);
      expect(find.byTooltip('Plus'), findsOneWidget);
    });

    testWidgets('aucune barre sous un message envoyé', (tester) async {
      final backend = _ScriptedBackend(<String>['Réponse']);
      await _pumpChat(tester, backend);

      await _send(tester, 'Ma question');
      await tester.pumpAndSettle();

      // Une seule barre : celle de la réponse, pas celle de la question.
      expect(find.byTooltip('Copier'), findsOneWidget);
    });

    testWidgets('copier place la réponse dans le presse-papier', (
      tester,
    ) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final backend = _ScriptedBackend(<String>['La réponse complète']);
      await _pumpChat(tester, backend);
      await _send(tester, 'Question');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Copier'));
      await tester.pumpAndSettle();

      expect(copied, <String>['La réponse complète']);
    });

    testWidgets('la note bascule et s’annule au second appui', (tester) async {
      final store = _RecordingStore();
      final backend = _ScriptedBackend(<String>['Réponse']);
      await _pumpChat(tester, backend, store: store);

      await _send(tester, 'Question');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Bonne réponse'));
      await tester.pumpAndSettle();
      expect(_lastAssistant(store).rating, MessageRating.up);

      // Second appui sur le même pouce : la note disparaît.
      await tester.tap(find.byTooltip('Bonne réponse'));
      await tester.pumpAndSettle();
      expect(_lastAssistant(store).rating, MessageRating.none);

      await tester.tap(find.byTooltip('Mauvaise réponse'));
      await tester.pumpAndSettle();
      expect(_lastAssistant(store).rating, MessageRating.down);
    });
  });

  group('sources', () {
    testWidgets('rien à afficher quand le modèle n’a pas cherché', (
      tester,
    ) async {
      final backend = _ScriptedBackend(<String>['Réponse sans source']);
      await _pumpChat(tester, backend);

      await _send(tester, 'Question');
      await tester.pumpAndSettle();

      expect(find.text('Sources'), findsNothing);
    });

    testWidgets('la liste des sources s’ouvre depuis le fil', (tester) async {
      final store = _RecordingStore(<ChatConversation>[
        ChatConversation(
          id: 1,
          title: 'Fil',
          updatedAt: DateTime(2026),
          messages: <ChatMessage>[
            const ChatMessage.user('Question'),
            const ChatMessage(
              role: ChatRole.assistant,
              content: 'Réponse ancrée',
              citations: <Citation>[
                Citation(url: 'https://exemple.fr/a', title: 'Article A'),
                Citation(url: 'https://autre.fr/b'),
              ],
            ),
          ],
        ),
      ]);
      await _pumpChat(tester, _ScriptedBackend(<String>['x']), store: store);

      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fil').last);
      await tester.pumpAndSettle();

      expect(find.text('Sources'), findsOneWidget);
      await tester.tap(find.text('Sources'));
      await tester.pumpAndSettle();

      expect(find.text('2 sources'), findsOneWidget);
      expect(find.text('Article A'), findsOneWidget);
      // Sans titre, l'hôte sert d'intitulé.
      expect(find.text('autre.fr'), findsWidgets);
    });
  });

  group('modification d’un message envoyé', () {
    testWidgets('l’appui long ouvre le menu, sans horodatage', (tester) async {
      final backend = _ScriptedBackend(<String>['Réponse']);
      await _pumpChat(tester, backend);

      await _send(tester, 'Ma question');
      await tester.pumpAndSettle();

      await tester.longPress(_inThread('Ma question'));
      await tester.pumpAndSettle();

      expect(find.text('Copier'), findsOneWidget);
      expect(find.text('Sélectionner le texte'), findsOneWidget);
      expect(find.text('Modifier le message'), findsOneWidget);
      expect(find.text('Partager'), findsOneWidget);
      // Aucune date ni heure dans ce menu.
      expect(find.textContaining(RegExp(r'\d{1,2}:\d{2}')), findsNothing);
    });

    testWidgets('modifier renvoie la question et remplace la suite', (
      tester,
    ) async {
      final backend = _ScriptedBackend(<String>['Première réponse']);
      await _pumpChat(tester, backend);

      await _send(tester, 'Question initiale');
      await tester.pumpAndSettle();
      expect(find.text('Première réponse'), findsOneWidget);

      backend.chunks = <String>['Deuxième réponse'];
      await tester.longPress(_inThread('Question initiale'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modifier le message'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Question corrigée');
      await tester.tap(find.text('Envoyer'));
      await tester.pumpAndSettle();

      // Le titre du fil garde le message d'origine : il se renomme à la
      // main, et le réécrire ici effacerait un nom choisi.
      expect(_inThread('Question initiale'), findsNothing);
      expect(find.text('Première réponse'), findsNothing);
      expect(_inThread('Question corrigée'), findsOneWidget);
      expect(find.text('Deuxième réponse'), findsOneWidget);
      expect(backend.calls.last.last.content, 'Question corrigée');
    });

    testWidgets('modifier ne touche pas au brouillon du composer', (
      tester,
    ) async {
      final backend = _ScriptedBackend(<String>['Réponse']);
      await _pumpChat(tester, backend);

      await _send(tester, 'Question');
      await tester.pumpAndSettle();

      // Un brouillon en cours d'écriture dans le composer.
      await tester.enterText(find.byType(TextField).last, 'Brouillon en cours');
      await tester.pump();

      await tester.longPress(_inThread('Question'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modifier le message'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Question revue');
      await tester.tap(find.text('Envoyer'));
      await tester.pumpAndSettle();

      final composer = tester
          .widgetList<TextField>(find.byType(TextField))
          .last;
      expect(
        composer.controller?.text,
        'Brouillon en cours',
        reason: 'reprendre un ancien message n’efface pas ce qu’on écrit',
      );
    });

    testWidgets('annuler la modification laisse le fil intact', (tester) async {
      final backend = _ScriptedBackend(<String>['Réponse']);
      await _pumpChat(tester, backend);

      await _send(tester, 'Question');
      await tester.pumpAndSettle();

      await tester.longPress(_inThread('Question'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modifier le message'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Jamais envoyé');
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(_inThread('Question'), findsOneWidget);
      expect(find.text('Réponse'), findsOneWidget);
      expect(backend.calls, hasLength(1));
    });
  });
}

/// Avance d'un nombre borné de trames : pendant une génération, la roue
/// d'attente tourne et `pumpAndSettle` ne rendrait jamais la main.
Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 5; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

ChatMessage _lastAssistant(_RecordingStore store) {
  return store.saved.last.single.messages.lastWhere(
    (message) => message.role == ChatRole.assistant,
  );
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).last, text);
  await tester.pump();
  await tester.tap(find.byTooltip('Envoyer'));
  await tester.pump();
}

Future<void> _pumpChat(
  WidgetTester tester,
  LocalLlmBackend backend, {
  _RecordingStore? store,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localLlmBackendProvider.overrideWithValue(backend),
        conversationStoreProvider.overrideWithValue(store ?? _RecordingStore()),
      ],
      child: localizedApp(home: ChatScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

class _RecordingStore implements ConversationStore {
  _RecordingStore([this._initial = const <ChatConversation>[]]);

  final List<ChatConversation> _initial;
  final List<List<ChatConversation>> saved = <List<ChatConversation>>[];

  @override
  Future<List<ChatConversation>> load() async => _initial;

  @override
  Future<void> save(List<ChatConversation> conversations) async =>
      saved.add(conversations);

  @override
  Future<void> clear() async {}
}

class _ScriptedBackend implements LocalLlmBackend {
  /// Le moteur local dit désormais pourquoi il s’est arrêté ; ce double
  /// n’a rien à écourter.
  @override
  String? get incompleteReason => null;

  _ScriptedBackend(this.chunks, {this.stream});

  List<String> chunks;

  /// Flux piloté par le test, quand il faut tenir la réponse ouverte.
  final Stream<String>? stream;
  final List<List<ChatMessage>> calls = <List<ChatMessage>>[];

  @override
  String get id => 'test';

  @override
  String get displayName => 'Backend de test';

  @override
  String? get loadedModelPath => '/models/test.gguf';

  @override
  Future<String> get nativeVersion async => 'test/0.0.0';

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
  }) {
    calls.add(List<ChatMessage>.of(messages));
    return stream ?? Stream<String>.fromIterable(chunks);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// Le texte tel qu'il apparaît dans le fil, et non le titre repris en haut de
/// l'écran : la barre du haut reprend le premier message de la conversation.
Finder _inThread(String text) => find.descendant(
  of: find.byKey(const ValueKey<String>('chat-content')),
  matching: find.text(text),
);
