// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  testWidgets('l’arrière-plan pendant la relecture n’efface pas l’historique', (
    tester,
  ) async {
    final store = _SlowStore(_oneConversation());
    await _pumpChat(tester, store);

    // La lecture n'est pas revenue : la liste en mémoire est encore vide.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    store.completeLoad();
    await tester.pumpAndSettle();

    expect(
      store.savedEmpty,
      isFalse,
      reason: 'un historique vide a été écrit par-dessus le fichier existant',
    );
  });

  testWidgets('un envoi pendant la relecture ne perd ni l’un ni l’autre', (
    tester,
  ) async {
    final store = _SlowStore(_oneConversation());
    await _pumpChat(tester, store);

    await tester.enterText(find.byType(TextField).first, 'Nouvelle question');
    await tester.pump();
    await tester.tap(find.byTooltip('Envoyer'));
    await tester.pump();

    store.completeLoad();
    await tester.pumpAndSettle();

    // L'ancien fil et le nouveau coexistent : ni la relecture n'écrase
    // l'envoi, ni l'envoi n'ampute l'historique relu.
    final titles = store.lastSaved.map((c) => c.title).toList();
    expect(titles, contains('Ancienne conversation'));
    expect(titles, contains('Nouvelle question'));
  });

  testWidgets('une lecture en échec n’autorise aucune écriture', (
    tester,
  ) async {
    final store = _SlowStore(_oneConversation(), failLoad: true);
    await _pumpChat(tester, store);

    store.completeLoad();
    await tester.pumpAndSettle();

    // Le fichier existe toujours sur disque : sa liste ne doit pas être
    // remplacée par la liste vide que l'écran a en mémoire. Ni l'envoi, ni
    // l'arrière-plan, ni la fermeture ne doivent déclencher d'écriture.
    // Le bandeau d'erreur recouvre le composeur : on l'écarte pour que
    // l'appui parte vraiment.
    expect(find.textContaining('historique'), findsWidgets);
    await tester.drag(
      find.textContaining('historique').first,
      const Offset(0, 300),
    );
    await _settle(tester);

    await tester.enterText(find.byType(TextField).first, 'Une question');
    await tester.pump();
    await tester.tap(find.byTooltip('Envoyer'));
    await _settle(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _settle(tester);

    await tester.pumpWidget(localizedApp(home: SizedBox.shrink()));
    await _settle(tester);

    expect(store.saveCalls, isEmpty);
  });

  testWidgets('fermer l’écran pendant la relecture n’efface rien', (
    tester,
  ) async {
    final store = _SlowStore(_oneConversation());
    await _pumpChat(tester, store);

    await tester.pumpWidget(localizedApp(home: SizedBox.shrink()));
    await tester.pump();

    store.completeLoad();
    await tester.pumpAndSettle();

    expect(store.savedEmpty, isFalse);
    expect(tester.takeException(), isNull);
  });

  group('fichier réel', _realFileTests);
}

/// Le fichier réel ne doit pas bouger d'un octet après un échec de lecture,
/// quoi que l'utilisateur fasse ensuite.
///
/// Ces contrôles sortent de `testWidgets` : son horloge simulée n'exécute pas
/// les entrées-sorties réelles, et une lecture de fichier n'y revient jamais.
/// Ils reproduisent donc à la main les trois moments qui déclenchaient une
/// écriture, sur le magasin et le fichier véritables.
void _realFileTests() {
  late Directory tempDirectory;
  late ConversationStore store;
  late File file;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('foxllm-restore');
    store = ConversationStore(
      applicationSupportDirectory: () async => tempDirectory,
    );
    file = File(
      '${tempDirectory.path}${Platform.pathSeparator}conversations.json',
    );
  });

  tearDown(() async => tempDirectory.delete(recursive: true));

  test('un fichier abîmé survit à l’envoi, à l’arrière-plan et à la '
      'fermeture', () async {
    // Structure non conforme : ce n'est pas un historique vide.
    const original = '{"conversations": "pas une liste"}';
    await file.writeAsString(original);

    // Ce que fait l'écran au lancement.
    var restored = true;
    final persister = ConversationPersister(
      save: store.save,
      // La liste en mémoire après un échec : vide, et sans rapport avec le
      // fichier.
      snapshot: () => const <ChatConversation>[],
      interval: const Duration(milliseconds: 1),
    );
    try {
      await store.load();
      restored = false;
    } on ConversationLoadException {
      persister.abandon();
    }
    expect(restored, isTrue, reason: 'la lecture aurait dû être refusée');

    // Un envoi, un passage en arrière-plan, puis la fermeture de l'écran.
    persister.schedule();
    persister.flush();
    persister.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(persister.writeCount, 0);
    expect(
      await file.readAsString(),
      original,
      reason: 'le fichier d’origine a été réécrit',
    );
  });

  test(
    'une récupération partielle n’autorise pas non plus l’écriture',
    () async {
      // Une seule conversation, lisible, mais dont deux messages sont perdus :
      // le défaut d'origine les écartait en silence, et la première écriture
      // réenregistrait la conversation sans eux.
      final original = jsonEncode(<String, Object?>{
        'conversations': <Object?>[
          <String, Object?>{
            'id': 1,
            'title': 'Valide',
            'updatedAt': DateTime(2026, 9, 13).toIso8601String(),
            'messages': <Object?>[
              <String, Object?>{'role': 'user', 'content': 'Bonjour'},
              'pas un objet',
              <String, Object?>{'role': 'inconnu', 'content': 'perdu'},
            ],
          },
        ],
      });
      await file.writeAsString(original);

      var recovered = const <ChatConversation>[];
      final persister = ConversationPersister(
        save: store.save,
        // Ce que l'écran affiche après la récupération partielle : moins que ce
        // que contient le fichier.
        snapshot: () => recovered,
        interval: const Duration(milliseconds: 1),
      );
      try {
        await store.load();
        fail('la lecture aurait dû signaler la perte');
      } on ConversationLoadException catch (error) {
        expect(error.failure, ConversationLoadFailure.partial);
        recovered = error.recovered;
        persister.abandon();
      }
      expect(recovered, hasLength(1));
      expect(recovered.single.messages, hasLength(1));

      // Un envoi, un passage en arrière-plan, puis la fermeture de l'écran.
      persister.schedule();
      persister.flush();
      persister.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(persister.writeCount, 0);
      expect(
        await file.readAsString(),
        original,
        reason: 'le fichier d’origine a été réécrit',
      );
    },
  );

  test('un historique valide reste enregistrable', () async {
    // Le garde-fou ne doit pas condamner le cas normal.
    await store.save(<ChatConversation>[
      ChatConversation(
        id: 1,
        title: 'Valide',
        updatedAt: DateTime.now(),
        messages: <ChatMessage>[const ChatMessage.user('Bonjour')],
      ),
    ]);
    expect(await store.load(), hasLength(1));
  });
}

List<ChatConversation> _oneConversation() => <ChatConversation>[
  ChatConversation(
    id: 1,
    title: 'Ancienne conversation',
    updatedAt: DateTime.now(),
    messages: <ChatMessage>[
      const ChatMessage.user('Ancienne question'),
      const ChatMessage.assistant('Ancienne réponse'),
    ],
  ),
];

Future<void> _pumpChat(WidgetTester tester, _SlowStore store) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localLlmBackendProvider.overrideWithValue(_ScriptedBackend()),
        conversationStoreProvider.overrideWithValue(store),
      ],
      child: localizedApp(home: ChatScreen()),
    ),
  );
  await tester.pump();
}

/// Magasin dont la lecture ne revient que lorsque le test le décide.
class _SlowStore implements ConversationStore {
  _SlowStore(this.seed, {this.failLoad = false});

  final List<ChatConversation> seed;
  final bool failLoad;
  final _gate = Completer<void>();

  final List<List<ChatConversation>> saveCalls = <List<ChatConversation>>[];

  List<ChatConversation> get lastSaved => saveCalls.last;

  /// Vrai si une écriture a remplacé le fichier par une liste vide.
  bool get savedEmpty => saveCalls.any((saved) => saved.isEmpty);

  void completeLoad() => _gate.complete();

  @override
  Future<List<ChatConversation>> load() async {
    await _gate.future;
    if (failLoad) {
      throw StateError('fichier illisible');
    }
    return seed;
  }

  @override
  Future<void> save(List<ChatConversation> conversations) async {
    saveCalls.add(List<ChatConversation>.of(conversations));
  }

  @override
  Future<void> clear() async {}
}

class _ScriptedBackend implements LocalLlmBackend {
  /// Le moteur local dit désormais pourquoi il s’est arrêté ; ce double
  /// n’a rien à écourter.
  @override
  String? get incompleteReason => null;

  @override
  String get id => 'scripted';

  @override
  String get displayName => 'Backend de test';

  @override
  String? get loadedModelPath => '/models/test.gguf';

  @override
  Future<String> get nativeVersion async => 'scripted/0.0.0';

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
  }) => Stream<String>.value('Réponse');

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// `pumpAndSettle` n'aboutit pas tant qu'une animation tourne, et la bulle
/// vide de l'assistant en fait tourner une : on avance d'un nombre borné
/// d'images.
Future<void> _settle(WidgetTester tester, [int frames = 40]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
