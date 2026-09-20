// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

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

import '../../support/localized_app.dart';

void main() {
  group('la rangée garde deux boutons', () {
    testWidgets('au repos, le micro tient la place de droite', (tester) async {
      await _pumpChat(tester, _QueueBackend());

      expect(_composerRow(tester), <String>[
        'Réflexion : désactivé',
        'Rechercher : désactivé',
        'Ajouter',
        'Maintenir pour dicter',
      ]);
    });

    testWidgets('écrire change le micro en Envoyer, sans en ajouter', (
      tester,
    ) async {
      await _pumpChat(tester, _QueueBackend());

      await tester.enterText(find.byType(TextField).first, 'Bonjour');
      await tester.pump();

      expect(_composerRow(tester), <String>[
        'Réflexion : désactivé',
        'Rechercher : désactivé',
        'Ajouter',
        'Envoyer',
      ]);
    });

    testWidgets('pendant la réponse, le micro devient Arrêter', (tester) async {
      final backend = _QueueBackend();
      await _pumpChat(tester, backend);

      await _send(tester, 'Bonjour');
      backend.emit('Je réflé');
      await tester.pump();

      expect(_composerRow(tester), <String>[
        'Réflexion : désactivé',
        'Rechercher : désactivé',
        'Ajouter',
        'Arrêter',
      ]);

      backend.finish();
      await _settle(tester);
    });

    testWidgets('écrire pendant la réponse remplace Arrêter par la mise en '
        'attente', (tester) async {
      final backend = _QueueBackend();
      await _pumpChat(tester, backend);

      await _send(tester, 'Bonjour');
      backend.emit('Je réflé');
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'Et aussi');
      await tester.pump();

      expect(_composerRow(tester), <String>[
        'Réflexion : désactivé',
        'Rechercher : désactivé',
        'Ajouter',
        'Mettre en attente',
      ]);

      backend.finish();
      await _settle(tester);
    });
  });

  group('texte du champ', () {
    testWidgets('les trois états se suivent', (tester) async {
      final backend = _QueueBackend();
      await _pumpChat(tester, backend);

      expect(find.text('Demander à FoxLLM'), findsOneWidget);

      await _send(tester, 'Bonjour');
      backend.emit('Je réflé');
      await tester.pump();

      expect(find.text('Mettre un message en attente…'), findsOneWidget);
      expect(find.text('Demander à FoxLLM'), findsNothing);

      backend.finish();
      await _settle(tester);

      expect(find.text('Demander à FoxLLM'), findsOneWidget);
    });
  });

  group('file d’attente', () {
    testWidgets('un message écrit pendant la réponse part après elle', (
      tester,
    ) async {
      final backend = _QueueBackend();
      await _pumpChat(tester, backend);

      await _send(tester, 'Premier');
      backend.emit('Réponse au premier');
      await tester.pump();

      // Mis en attente : le champ se vide, la réponse en cours continue.
      await _send(tester, 'Second');

      expect(backend.generateCalls, hasLength(1));
      expect(backend.stopCalls, 0);
      expect(_draft(tester), isEmpty);

      backend.finish();
      await _settle(tester);

      // La réponse terminée libère la voie : le message part tout seul, avec
      // l'historique complet derrière lui.
      expect(backend.generateCalls, hasLength(2));
      expect(backend.generateCalls.last.map((m) => m.content), <String>[
        'Premier',
        'Réponse au premier',
        'Second',
      ]);
      expect(find.text('Second'), findsOneWidget);

      backend.finish();
      await _settle(tester);
    });

    testWidgets('plusieurs messages partent dans leur ordre', (tester) async {
      final backend = _QueueBackend();
      await _pumpChat(tester, backend);

      await _send(tester, 'Premier');
      await tester.pump();
      await _send(tester, 'Second');
      await _send(tester, 'Troisième');

      expect(backend.generateCalls, hasLength(1));

      backend.finish();
      await _settle(tester);
      expect(backend.generateCalls.last.last.content, 'Second');

      backend.finish();
      await _settle(tester);
      expect(backend.generateCalls.last.last.content, 'Troisième');

      backend.finish();
      await _settle(tester);

      expect(backend.generateCalls, hasLength(3));
      expect(find.text('Troisième'), findsOneWidget);
    });

    testWidgets('Arrêter n’envoie rien : il interrompt', (tester) async {
      final backend = _QueueBackend();
      await _pumpChat(tester, backend);

      await _send(tester, 'Bonjour');
      backend.emit('Je réflé');
      await tester.pump();

      await tester.tap(find.byTooltip('Arrêter'));
      await tester.pump();

      expect(backend.stopCalls, 1);
      expect(backend.generateCalls, hasLength(1));

      backend.finish();
      await _settle(tester);
    });

    testWidgets('une nouvelle conversation vide la file', (tester) async {
      final backend = _QueueBackend();
      await _pumpChat(tester, backend);

      await _send(tester, 'Premier');
      backend.emit('Réponse');
      await tester.pump();
      await _send(tester, 'En attente');

      await tester.tap(find.byTooltip('Nouveau chat'));
      await tester.pump();

      backend.finish();
      await _settle(tester);

      // Le message en attente appartenait au fil qu'on vient de quitter.
      expect(backend.generateCalls, hasLength(1));
      expect(find.text('En attente'), findsNothing);
    });
  });
}

/// Boutons de la rangée sous le champ, de gauche à droite, par leur bulle
/// d'aide. Un bouton en trop y apparaîtrait, quel que soit son libellé : c'est
/// ce que ces tests surveillent.
List<String> _composerRow(WidgetTester tester) {
  final fieldBottom = tester.getRect(find.byType(TextField).first).bottom;
  final row = <(double, String)>[];
  for (final element in find.byType(Tooltip).evaluate()) {
    final box = element.renderObject;
    if (box is! RenderBox || !box.hasSize) {
      continue;
    }
    final origin = box.localToGlobal(Offset.zero);
    if (origin.dy < fieldBottom) {
      continue;
    }
    row.add((origin.dx, (element.widget as Tooltip).message!));
  }
  row.sort((a, b) => a.$1.compareTo(b.$1));
  return <String>[for (final entry in row) entry.$2];
}

String _draft(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).first).controller!.text;

/// Écrit puis appuie sur le bouton de droite, quel que soit son rôle du moment.
Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump();
  final send = find.byTooltip('Envoyer');
  await tester.tap(send.evaluate().isNotEmpty ? send : _queueButton);
  await tester.pump();
}

final _queueButton = find.byTooltip('Mettre en attente');

/// Avance de quelques frames sans attendre l'immobilité : pendant une
/// génération, l'indicateur de progression tourne et `pumpAndSettle` ne rend
/// jamais la main.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _pumpChat(WidgetTester tester, _QueueBackend backend) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(backend.closeAll);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localLlmBackendProvider.overrideWithValue(backend),
        conversationStoreProvider.overrideWithValue(_EmptyStore()),
      ],
      child: localizedApp(home: ChatScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Backend dont chaque réponse reste ouverte jusqu'à ce que le test la ferme.
///
/// C'est ce qui permet d'écrire pendant qu'une réponse est en cours, puis de
/// vérifier ce qui part une fois la voie libre.
class _QueueBackend implements LocalLlmBackend {
  final List<List<ChatMessage>> generateCalls = <List<ChatMessage>>[];
  final List<StreamController<String>> _streams = <StreamController<String>>[];
  int stopCalls = 0;

  StreamController<String> get _current => _streams.last;

  void emit(String chunk) => _current.add(chunk);

  /// Termine la réponse en cours, comme un moteur qui a fini de parler.
  void finish() {
    if (_streams.isNotEmpty && !_current.isClosed) {
      unawaited(_current.close());
    }
  }

  void closeAll() {
    for (final stream in _streams) {
      if (!stream.isClosed) {
        unawaited(stream.close());
      }
    }
  }

  @override
  String get id => 'queue';

  @override
  String get displayName => 'Backend de test';

  @override
  String? get loadedModelPath => '/models/test.gguf';

  @override
  Future<String> get nativeVersion async => 'queue/0.0.0';

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
    generateCalls.add(List<ChatMessage>.of(messages));
    final stream = StreamController<String>();
    _streams.add(stream);
    return stream.stream;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    finish();
  }

  @override
  Future<void> dispose() async {}
}

class _EmptyStore implements ConversationStore {
  @override
  Future<List<ChatConversation>> load() async => <ChatConversation>[];

  @override
  Future<void> save(List<ChatConversation> conversations) async {}

  @override
  Future<void> clear() async {}
}
