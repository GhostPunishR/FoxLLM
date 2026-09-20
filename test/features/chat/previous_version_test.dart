// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/storage/last_model_store.dart';
import 'package:foxllm/features/chat/chat_screen.dart';
import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/features/chat/conversations/conversation_store.dart';
import 'package:foxllm/llm/backend/local_backend_provider.dart';
import 'package:foxllm/llm/backend/local_llm_backend.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm_native/foxllm_native.dart';

/// Un remplacement qui tourne mal laisse deux versions du fil : celle qu'on
/// vient d'obtenir, souvent partielle, et celle qu'elle a remplacée. Les deux
/// doivent survivre au temps, à la navigation et au redémarrage.
void main() {
  group('la version remplacée reste reprenable', () {
    testWidgets('une erreur avant le premier fragment rend le fil intact, '
        'sans rien à reprendre', (tester) async {
      final backend = _Backend();
      final store = _RecordingStore(seed: _thread());
      await _pumpThread(tester, backend, store);

      await _regenerate(tester);
      backend.fail('le fournisseur a abandonné');
      await _settle(tester);

      expect(_inThread(tester, 'Première réponse'), isTrue);
      // Rien n'a été remplacé : il n'y a aucune version à proposer.
      expect(find.text('Version précédente conservée'), findsNothing);
      // Le fil est revenu tout seul : il faut le dire, sinon l'utilisateur
      // croit que sa régénération a simplement disparu.
      expect(
        find.textContaining('Réponse précédente conservée'),
        findsOneWidget,
        reason: 'un rétablissement muet ne se distingue pas d’un oubli',
      );
    });

    testWidgets('une erreur après des fragments garde les deux versions', (
      tester,
    ) async {
      final backend = _Backend();
      final store = _RecordingStore(seed: _thread());
      await _pumpThread(tester, backend, store);

      await _regenerate(tester);
      backend.emit('Début de réponse');
      await _settle(tester);
      backend.fail('le fournisseur a abandonné');
      await _settle(tester);

      // Le résultat partiel est à l'écran, la version d'avant est conservée.
      expect(_inThread(tester, 'Début de réponse'), isTrue);
      expect(find.text('Version précédente conservée'), findsOneWidget);
      expect(_saved(store).previousMessages?.map((m) => m.content), <String>[
        'Ma question',
        'Première réponse',
      ]);
    });

    testWidgets('elle survit à l’attente, à la navigation et au rechargement', (
      tester,
    ) async {
      final backend = _Backend();
      final store = _RecordingStore(seed: _thread(withSecond: true));
      await _pumpThread(tester, backend, store);

      await _regenerate(tester);
      backend.emit('Début de réponse');
      await _settle(tester);
      backend.fail('le fournisseur a abandonné');
      await _settle(tester);
      expect(find.text('Version précédente conservée'), findsOneWidget);

      // Le défaut d'origine : la reprise tenait à l'action d'un bandeau de dix
      // secondes. Bien après, elle doit toujours être là.
      await tester.pump(const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 20));
      expect(find.text('Version précédente conservée'), findsOneWidget);

      // Aller voir ailleurs puis revenir ne l'efface pas.
      await _openThread(tester, 'Autre fil');
      expect(find.text('Version précédente conservée'), findsNothing);
      await _openThread(tester, 'Ma question');
      expect(find.text('Version précédente conservée'), findsOneWidget);

      // Et un relancement de l'application la retrouve : le fil est relu
      // depuis le JSON réellement écrit.
      final reread = store.saveCalls.last
          .map((c) => ChatConversation.fromJson(c.toJson()))
          .whereType<ChatConversation>()
          .toList();
      await _pumpChat(tester, _Backend(), _RecordingStore(seed: reread));
      await _openThread(tester, 'Ma question');

      expect(find.text('Version précédente conservée'), findsOneWidget);
      expect(_inThread(tester, 'Début de réponse'), isTrue);
    });

    testWidgets('rétablir rend l’ancienne version sans perdre la partielle', (
      tester,
    ) async {
      final backend = _Backend();
      final store = _RecordingStore(seed: _thread());
      await _pumpThread(tester, backend, store);

      await _regenerate(tester);
      backend.emit('Début de réponse');
      await _settle(tester);
      backend.fail('le fournisseur a abandonné');
      await _settle(tester);

      await tester.tap(find.text('Rétablir'));
      await _settle(tester);

      expect(_inThread(tester, 'Première réponse'), isTrue);
      expect(_inThread(tester, 'Début de réponse'), isFalse);
      // Le résultat partiel n'est pas jeté : il a pris la place de l'autre.
      expect(_saved(store).previousMessages?.map((m) => m.content), <String>[
        'Ma question',
        'Début de réponse',
      ]);

      // Le geste se refait dans l'autre sens.
      await tester.tap(find.text('Rétablir'));
      await _settle(tester);
      expect(_inThread(tester, 'Début de réponse'), isTrue);
      expect(_saved(store).previousMessages?.map((m) => m.content), <String>[
        'Ma question',
        'Première réponse',
      ]);
    });

    testWidgets('un remplacement réussi ne propose aucune restauration', (
      tester,
    ) async {
      final backend = _Backend();
      final store = _RecordingStore(seed: _thread());
      await _pumpThread(tester, backend, store);

      await _regenerate(tester);
      backend.emit('Seconde réponse');
      await _settle(tester);
      backend.finish();
      await _settle(tester);

      expect(_inThread(tester, 'Seconde réponse'), isTrue);
      expect(find.text('Version précédente conservée'), findsNothing);
      expect(_saved(store).previousMessages, isNull);
    });

    testWidgets('une modification bénéficie de la même protection', (
      tester,
    ) async {
      final backend = _Backend();
      final store = _RecordingStore(seed: _thread());
      await _pumpThread(tester, backend, store);

      await tester.longPress(_threadFinder('Ma question'));
      await _settle(tester);
      await tester.tap(find.text('Modifier le message'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).first, 'Question revue');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Envoyer'));
      await _settle(tester);

      backend.emit('Réponse partielle');
      await _settle(tester);
      backend.fail('le fournisseur a abandonné');
      await _settle(tester);

      expect(find.text('Version précédente conservée'), findsOneWidget);
      expect(_saved(store).previousMessages?.map((m) => m.content), <String>[
        'Ma question',
        'Première réponse',
      ]);
    });

    testWidgets('le rétablissement est éteint pendant la préparation et la '
        'génération, puis revient', (tester) async {
      final backend = _Backend();
      final store = _RecordingStore(seed: _thread(withPrevious: true));
      await _pumpThread(tester, backend, store);
      expect(_restoreAction(tester), isNotNull);

      // La préparation de l'envoi est retenue : le fil appartient déjà à
      // l'opération qui démarre.
      backend.holdNextPreparation();
      await tester.enterText(find.byType(TextField).first, 'Nouvelle question');
      await tester.pump();
      await tester.tap(find.byTooltip('Envoyer'));
      await _settle(tester);
      expect(backend.generateCalls, isEmpty);
      expect(_restoreAction(tester), isNull);

      // La préparation aboutit, le flux commence : toujours pas.
      backend.completePreparation();
      await _settle(tester);
      backend.emit('Nouvelle ');
      await _settle(tester);
      expect(_restoreAction(tester), isNull);

      // Le défaut d'origine : l'échange remplaçait le fil sans arrêter la
      // génération, et le fragment suivant écrasait le dernier message de la
      // version rétablie.
      await tester.tap(find.text('Rétablir'), warnIfMissed: false);
      await _settle(tester);
      backend.emit('réponse');
      await _settle(tester);

      expect(_inThread(tester, 'Nouvelle réponse'), isTrue);
      expect(_inThread(tester, 'Version d’avant'), isFalse);
      expect(_saved(store).previousMessages?.map((m) => m.content), <String>[
        'Ma question',
        'Version d’avant',
      ]);

      // La génération se termine : le rétablissement redevient possible.
      backend.finish();
      await _settle(tester);
      expect(_restoreAction(tester), isNotNull);

      await tester.tap(find.text('Rétablir'));
      await _settle(tester);

      expect(_inThread(tester, 'Version d’avant'), isTrue);
      expect(_saved(store).messages.map((m) => m.content), <String>[
        'Ma question',
        'Version d’avant',
      ]);
      expect(_saved(store).previousMessages?.last.content, 'Nouvelle réponse');
    });

    testWidgets('il revient aussi après une génération en échec', (
      tester,
    ) async {
      final backend = _Backend();
      final store = _RecordingStore(seed: _thread(withPrevious: true));
      await _pumpThread(tester, backend, store);

      await tester.enterText(find.byType(TextField).first, 'Nouvelle question');
      await tester.pump();
      await tester.tap(find.byTooltip('Envoyer'));
      await _settle(tester);
      expect(_restoreAction(tester), isNull);

      backend.fail('le fournisseur a abandonné');
      await _settle(tester);

      expect(_restoreAction(tester), isNotNull);
      await tester.tap(find.text('Rétablir'));
      await _settle(tester);
      expect(_inThread(tester, 'Version d’avant'), isTrue);
    });

    testWidgets('il revient aussi après un arrêt demandé', (tester) async {
      final backend = _Backend();
      final store = _RecordingStore(seed: _thread(withPrevious: true));
      await _pumpThread(tester, backend, store);

      await tester.enterText(find.byType(TextField).first, 'Nouvelle question');
      await tester.pump();
      await tester.tap(find.byTooltip('Envoyer'));
      await _settle(tester);
      backend.emit('Un début');
      await _settle(tester);
      expect(_restoreAction(tester), isNull);

      await tester.tap(find.byTooltip('Arrêter'));
      await _settle(tester);

      expect(_restoreAction(tester), isNotNull);
      await tester.tap(find.text('Rétablir'));
      await _settle(tester);
      expect(_inThread(tester, 'Version d’avant'), isTrue);
    });

    testWidgets('oublier la version conservée la retire pour de bon', (
      tester,
    ) async {
      final backend = _Backend();
      final store = _RecordingStore(seed: _thread());
      await _pumpThread(tester, backend, store);

      await _regenerate(tester);
      backend.emit('Début de réponse');
      await _settle(tester);
      backend.fail('le fournisseur a abandonné');
      await _settle(tester);

      await tester.tap(find.byTooltip('Oublier la version précédente'));
      await _settle(tester);

      expect(find.text('Version précédente conservée'), findsNothing);
      expect(_saved(store).previousMessages, isNull);
    });
  });

  group('quitter un fil en pleine régénération', () {
    testWidgets('garde le résultat partiel et la version remplacée', (
      tester,
    ) async {
      final backend = _Backend();
      final store = _RecordingStore(seed: _thread(withSecond: true));
      await _pumpThread(tester, backend, store);

      await _regenerate(tester);
      backend.emit('Début ');
      await _settle(tester);
      backend.emit('de réponse');
      await _settle(tester);

      // On quitte A avant la fin, puis l'opération de A se termine tard.
      await _openThread(tester, 'Autre fil');
      backend.finish();
      await _settle(tester);

      // B n'a rien reçu de tout cela.
      expect(_inThread(tester, 'Autre réponse'), isTrue);
      expect(_inThread(tester, 'Début de réponse'), isFalse);
      final other = store.saveCalls.last.firstWhere((c) => c.id == 2);
      expect(other.messages.map((m) => m.content), <String>[
        'Autre fil',
        'Autre réponse',
      ]);
      expect(other.previousMessages, isNull);

      // Le défaut d'origine : le fil quitté gardait la réponse partielle et
      // perdait la version qu'elle remplaçait.
      final abandoned = _saved(store);
      expect(abandoned.messages.map((m) => m.content), <String>[
        'Ma question',
        'Début de réponse',
      ]);
      expect(abandoned.messages.last.outcome, GenerationOutcome.cancelled);
      expect(abandoned.previousMessages?.map((m) => m.content), <String>[
        'Ma question',
        'Première réponse',
      ]);

      // De retour dans A, les deux versions sont là.
      await _openThread(tester, 'Ma question');
      expect(_inThread(tester, 'Début de réponse'), isTrue);
      expect(find.text('Version précédente conservée'), findsOneWidget);
      await tester.tap(find.text('Rétablir'));
      await _settle(tester);
      expect(_inThread(tester, 'Première réponse'), isTrue);
    });

    testWidgets('un échec tardif est noté comme tel, et rien n’est perdu', (
      tester,
    ) async {
      final backend = _Backend();
      final store = _RecordingStore(seed: _thread(withSecond: true));
      await _pumpThread(tester, backend, store);

      await _regenerate(tester);
      backend.emit('Début de réponse');
      await _settle(tester);

      // Le moteur accuse l'arrêt mais son flux ne se referme pas tout de
      // suite : c'est une erreur qui y met fin, après la navigation.
      backend.closeOnStop = false;
      await _openThread(tester, 'Autre fil');
      backend.fail('le fournisseur a abandonné');
      await _settle(tester);

      final abandoned = _saved(store);
      expect(abandoned.messages.last.content, 'Début de réponse');
      expect(abandoned.messages.last.outcome, GenerationOutcome.failed);
      expect(abandoned.previousMessages?.last.content, 'Première réponse');
    });

    testWidgets('les deux versions survivent au rechargement du stockage', (
      tester,
    ) async {
      final backend = _Backend();
      final store = _RecordingStore(seed: _thread(withSecond: true));
      await _pumpThread(tester, backend, store);

      await _regenerate(tester);
      backend.emit('Début de réponse');
      await _settle(tester);
      await _openThread(tester, 'Autre fil');
      backend.finish();
      await _settle(tester);

      // Relu depuis le JSON réellement écrit, comme au lancement suivant.
      final reread = store.saveCalls.last
          .map((c) => ChatConversation.fromJson(c.toJson()))
          .whereType<ChatConversation>()
          .toList();
      await _pumpChat(tester, _Backend(), _RecordingStore(seed: reread));
      await _openThread(tester, 'Ma question');

      expect(_inThread(tester, 'Début de réponse'), isTrue);
      expect(find.text('Version précédente conservée'), findsOneWidget);
      await tester.tap(find.text('Rétablir'));
      await _settle(tester);
      expect(_inThread(tester, 'Première réponse'), isTrue);
    });

    testWidgets('un fil supprimé avant le retour tardif ne renaît pas', (
      tester,
    ) async {
      final backend = _Backend();
      final store = _RecordingStore(seed: _thread(withSecond: true));
      await _pumpThread(tester, backend, store);

      await _regenerate(tester);
      backend.emit('Début de réponse');
      await _settle(tester);

      await tester.tap(find.byTooltip('Menu'));
      await _settle(tester);
      await tester.tap(find.byTooltip('Actions de la conversation').first);
      await _settle(tester);
      await tester.tap(find.text('Supprimer'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await _settle(tester);

      backend.finish();
      await _settle(tester);

      expect(
        store.saveCalls.last.where((c) => c.id == 1),
        isEmpty,
        reason: 'le fil supprimé est revenu',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('la réparation tardive n’efface pas le message qui attendait', (
      tester,
    ) async {
      final backend = _Backend();
      final store = _RecordingStore(seed: _thread(withSecond: true));
      await _pumpThread(tester, backend, store);

      await _regenerate(tester);
      backend.emit('Ancien début');
      await _settle(tester);

      // Le flux de la première opération reste ouvert après la navigation.
      backend.closeOnStop = false;
      await _openThread(tester, 'Autre fil');
      await _openThread(tester, 'Ma question');

      // Un second message est écrit : l'envoi précédent n'ayant pas rendu la
      // main, il rejoint la file.
      await tester.enterText(find.byType(TextField).first, 'Nouvelle question');
      await tester.pump();
      await tester.tap(find.byTooltip('Envoyer'));
      await _settle(tester);
      expect(find.text('1 message en attente'), findsOneWidget);

      // La première opération se termine enfin : elle répare le fil qu'on
      // avait quitté, puis la file repart dans ce même fil.
      backend.finishAt(0);
      await _settle(tester);
      backend.emit('Nouvelle réponse');
      await _settle(tester);
      backend.finish();
      await _settle(tester);

      final saved = _saved(store);
      expect(saved.messages.map((m) => m.content), <String>[
        'Ma question',
        'Ancien début',
        'Nouvelle question',
        'Nouvelle réponse',
      ]);
      // La réparation tardive n'a pas rembobiné le fil, et la version
      // remplacée reste reprenable.
      expect(saved.previousMessages?.map((m) => m.content), <String>[
        'Ma question',
        'Première réponse',
      ]);
      expect(_inThread(tester, 'Nouvelle réponse'), isTrue);
    });
  });
}

// ---- utilitaires ----------------------------------------------------------

List<ChatConversation> _thread({
  bool withSecond = false,
  bool withPrevious = false,
}) => <ChatConversation>[
  ChatConversation(
    id: 1,
    title: 'Ma question',
    updatedAt: DateTime(2026, 9, 14, 10),
    messages: <ChatMessage>[
      const ChatMessage.user('Ma question'),
      const ChatMessage.assistant('Première réponse'),
    ],
    previousMessages: withPrevious
        ? <ChatMessage>[
            const ChatMessage.user('Ma question'),
            const ChatMessage.assistant('Version d’avant'),
          ]
        : null,
  ),
  if (withSecond)
    ChatConversation(
      id: 2,
      title: 'Autre fil',
      updatedAt: DateTime(2026, 9, 14, 9),
      messages: <ChatMessage>[
        const ChatMessage.user('Autre fil'),
        const ChatMessage.assistant('Autre réponse'),
      ],
    ),
];

ChatConversation _saved(_RecordingStore store) =>
    store.saveCalls.last.firstWhere((c) => c.id == 1);

Finder _threadFinder(String text) => find.descendant(
  of: find.byKey(const ValueKey<String>('chat-content')),
  matching: find.text(text),
);

bool _inThread(WidgetTester tester, String text) =>
    _threadFinder(text).evaluate().isNotEmpty;

Future<void> _regenerate(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Plus'));
  await _settle(tester);
  await tester.tap(find.text('Régénérer la réponse'));
  await _settle(tester);
}

Future<void> _openThread(WidgetTester tester, String title) async {
  await tester.tap(find.byTooltip('Menu'));
  await _settle(tester);
  await tester.tap(find.text(title).last);
  await _settle(tester);
}

/// Avance sans attendre l'immobilité : l'indicateur d'une génération en cours
/// tourne sans fin.
Future<void> _settle(WidgetTester tester, [int frames = 40]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pumpThread(
  WidgetTester tester,
  _Backend backend,
  _RecordingStore store,
) async {
  await _pumpChat(tester, backend, store);
  await _openThread(tester, 'Ma question');
}

Future<void> _pumpChat(
  WidgetTester tester,
  _Backend backend,
  _RecordingStore store,
) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(backend.closeAll);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localLlmBackendProvider.overrideWithValue(backend),
        conversationStoreProvider.overrideWithValue(store),
        lastModelStoreProvider.overrideWithValue(
          _FakeLastModelStore('/models/memorise.gguf'),
        ),
      ],
      child: const MaterialApp(home: ChatScreen()),
    ),
  );
  await _settle(tester);
}

/// Action du bouton de rétablissement : `null` quand il est éteint.
VoidCallback? _restoreAction(WidgetTester tester) => tester
    .widget<TextButton>(find.widgetWithText(TextButton, 'Rétablir'))
    .onPressed;

class _FakeLastModelStore implements LastModelStore {
  _FakeLastModelStore(this.path);

  final String? path;

  @override
  Future<String?> load() async => path;

  @override
  Future<void> save(String path) async {}

  @override
  Future<void> clear() async {}
}

class _RecordingStore implements ConversationStore {
  _RecordingStore({this.seed = const <ChatConversation>[]});

  final List<ChatConversation> seed;
  final List<List<ChatConversation>> saveCalls = <List<ChatConversation>>[];

  @override
  Future<List<ChatConversation>> load() async => seed;

  @override
  Future<void> save(List<ChatConversation> conversations) async {
    saveCalls.add(
      conversations
          .map(
            (c) => ChatConversation(
              id: c.id,
              title: c.title,
              updatedAt: c.updatedAt,
              messages: List<ChatMessage>.of(c.messages),
              previousMessages: c.previousMessages == null
                  ? null
                  : List<ChatMessage>.of(c.previousMessages!),
            ),
          )
          .toList(),
    );
  }

  @override
  Future<void> clear() async {}
}

/// Moteur de test : ses réponses restent ouvertes jusqu'à ce que le test en
/// décide.
class _Backend implements LocalLlmBackend {
  final List<StreamController<String>> _streams = <StreamController<String>>[];
  final List<List<ChatMessage>> generateCalls = <List<ChatMessage>>[];

  String? _path = '/models/test.gguf';
  Completer<void>? _loadGate;

  /// Referme le modèle : la préparation suivante devra le rouvrir, et cette
  /// ouverture n'aboutira que sur commande.
  void holdNextPreparation() {
    _path = null;
    _loadGate = Completer<void>();
  }

  void completePreparation() {
    final gate = _loadGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  void emit(String chunk) {
    if (_streams.isNotEmpty && !_streams.last.isClosed) {
      _streams.last.add(chunk);
    }
  }

  void finish() {
    if (_streams.isNotEmpty && !_streams.last.isClosed) {
      unawaited(_streams.last.close());
    }
  }

  /// Termine une réponse précise, pas forcément la dernière ouverte.
  void finishAt(int index) {
    if (index < _streams.length && !_streams[index].isClosed) {
      unawaited(_streams[index].close());
    }
  }

  void failAt(int index, String message) {
    if (index < _streams.length && !_streams[index].isClosed) {
      _streams[index].addError(StateError(message));
      unawaited(_streams[index].close());
    }
  }

  /// Faux pour un moteur qui accuse l'arrêt sans refermer son flux tout de
  /// suite : la réponse s'y termine alors plus tard, parfois sur une erreur.
  bool closeOnStop = true;

  void fail(String message) {
    if (_streams.isNotEmpty && !_streams.last.isClosed) {
      _streams.last.addError(StateError(message));
      unawaited(_streams.last.close());
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
  String get id => 'test';

  @override
  String get displayName => 'Backend de test';

  @override
  String? get loadedModelPath => _path;

  @override
  Future<String> get nativeVersion async => 'test/0.0.0';

  @override
  Future<bool> get isModelLoaded async => true;

  @override
  Future<FoxLlmModelInfo?> get modelInfo async => null;

  @override
  Future<FoxLlmGenerationStats?> get lastGenerationStats async => null;

  @override
  Future<void> loadModel(String path) async {
    final gate = _loadGate;
    if (gate != null) {
      await gate.future;
    }
    _path = path;
  }

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
    if (closeOnStop) {
      finish();
    }
  }

  @override
  Future<void> dispose() async {}
}
