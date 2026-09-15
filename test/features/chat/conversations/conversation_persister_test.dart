// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/features/chat/conversations/conversation_store.dart';
import 'package:foxllm/llm/model/chat_message.dart';

ChatConversation _conversation(int id, String content) {
  return ChatConversation(
    id: id,
    title: 'fil $id',
    updatedAt: DateTime(2026, 1, 1),
    messages: <ChatMessage>[ChatMessage.assistant(content)],
  );
}

void main() {
  group('regroupement des écritures', () {
    testWidgets('une rafale de fragments ne déclenche qu’une écriture', (
      tester,
    ) async {
      final written = <List<ChatConversation>>[];
      var live = <ChatConversation>[_conversation(1, '')];
      final persister = ConversationPersister(
        save: (List<ChatConversation> conversations) async =>
            written.add(conversations),
        snapshot: () => List<ChatConversation>.of(live),
        interval: const Duration(seconds: 2),
      );
      addTearDown(persister.dispose);
      // L'écran libère les écritures une fois l'historique relu.
      persister.release();

      // Cinquante fragments, comme une génération locale ordinaire.
      for (var index = 0; index < 50; index++) {
        live = <ChatConversation>[_conversation(1, 'a' * (index + 1))];
        persister.schedule();
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(written.length, lessThanOrEqualTo(1));

      // La fin de génération impose l'état définitif.
      persister.flush();
      expect(written.last.single.messages.single.content, 'a' * 50);
    });

    testWidgets('la fréquence reste bornée sur une longue génération', (
      tester,
    ) async {
      var writes = 0;
      final persister = ConversationPersister(
        save: (List<ChatConversation> conversations) async => writes++,
        snapshot: () => <ChatConversation>[_conversation(1, 'x')],
        interval: const Duration(seconds: 2),
      );
      addTearDown(persister.dispose);
      // L'écran libère les écritures une fois l'historique relu.
      persister.release();

      // Dix secondes de fragments à 20 ms : cinq cents appels.
      for (var index = 0; index < 500; index++) {
        persister.schedule();
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(writes, lessThanOrEqualTo(6));
      expect(writes, greaterThan(0), reason: 'il faut bien écrire parfois');
    });

    testWidgets('une écriture différée ne ressuscite pas un fil supprimé', (
      tester,
    ) async {
      final written = <List<ChatConversation>>[];
      var live = <ChatConversation>[
        _conversation(1, 'bonjour'),
        _conversation(2, 'salut'),
      ];
      final persister = ConversationPersister(
        save: (List<ChatConversation> conversations) async =>
            written.add(conversations),
        snapshot: () => List<ChatConversation>.of(live),
        interval: const Duration(seconds: 2),
      );
      addTearDown(persister.dispose);
      // L'écran libère les écritures une fois l'historique relu.
      persister.release();

      persister.schedule();
      // Suppression avant que l'écriture différée ne parte.
      live = <ChatConversation>[_conversation(2, 'salut')];
      persister.flush();

      await tester.pump(const Duration(seconds: 5));

      expect(written, hasLength(1));
      expect(written.single.map((conversation) => conversation.id), <int>[
        2,
      ], reason: 'l’état est relu au moment d’écrire, pas figé avant');
    });

    testWidgets('un changement ponctuel part même sans planification', (
      tester,
    ) async {
      var writes = 0;
      final persister = ConversationPersister(
        save: (List<ChatConversation> conversations) async => writes++,
        snapshot: () => <ChatConversation>[_conversation(1, 'renommé')],
        interval: const Duration(seconds: 2),
      );
      addTearDown(persister.dispose);
      // L'écran libère les écritures une fois l'historique relu.
      persister.release();

      // Un renommage n'est précédé d'aucun `schedule()`.
      persister.flush();

      expect(writes, 1);
    });

    testWidgets('la fermeture écrit ce qui restait en attente', (tester) async {
      var writes = 0;
      final persister = ConversationPersister(
        save: (List<ChatConversation> conversations) async => writes++,
        snapshot: () => <ChatConversation>[_conversation(1, 'partiel')],
        interval: const Duration(seconds: 2),
      );
      // L'écran libère les écritures une fois l'historique relu.
      persister.release();

      persister.schedule();
      persister.dispose();

      expect(writes, 1, reason: 'les fragments reçus ne sont pas perdus');

      // Plus rien ne part après la fermeture.
      persister.schedule();
      persister.flush();
      await tester.pump(const Duration(seconds: 5));
      expect(writes, 1);
    });
  });

  group('retenue jusqu’à la relecture', () {
    testWidgets('rien ne part tant que l’historique n’est pas relu', (
      tester,
    ) async {
      var writes = 0;
      final persister = ConversationPersister(
        save: (List<ChatConversation> conversations) async => writes++,
        snapshot: () => <ChatConversation>[_conversation(1, 'x')],
        interval: const Duration(seconds: 2),
      );
      addTearDown(persister.dispose);

      expect(persister.isHeld, isTrue);
      persister.schedule();
      persister.flush();
      await tester.pump(const Duration(seconds: 5));

      expect(writes, 0, reason: 'la liste en mémoire est encore vide');
    });

    testWidgets('les demandes retenues partent à la libération', (
      tester,
    ) async {
      var writes = 0;
      final persister = ConversationPersister(
        save: (List<ChatConversation> conversations) async => writes++,
        snapshot: () => <ChatConversation>[_conversation(1, 'x')],
        interval: const Duration(seconds: 2),
      );
      addTearDown(persister.dispose);

      persister.flush();
      expect(writes, 0);

      persister.release();
      expect(writes, 1, reason: 'la demande retenue n’est pas perdue');
      expect(persister.isHeld, isFalse);
    });

    testWidgets('une relecture abandonnée interdit toute écriture', (
      tester,
    ) async {
      var writes = 0;
      final persister = ConversationPersister(
        save: (List<ChatConversation> conversations) async => writes++,
        snapshot: () => <ChatConversation>[_conversation(1, 'x')],
        interval: const Duration(seconds: 2),
      );
      addTearDown(persister.dispose);

      persister.abandon();
      persister.flush();
      // Même une libération tardive ne rouvre pas la porte : le fichier reste
      // tel qu'il est plutôt que d'être remplacé par une liste vide.
      persister.release();
      await tester.pump(const Duration(seconds: 5));

      expect(writes, 0);
      expect(persister.isHeld, isTrue);
    });
  });

  group('stockage lent', () {
    testWidgets('une seule sauvegarde à la fois', (tester) async {
      final saver = _GatedSaver();
      final persister = _persister(saver, () => saver.live);
      addTearDown(persister.dispose);
      // L'écran libère les écritures une fois l'historique relu.
      persister.release();

      persister.flush();
      expect(saver.started, 1);

      // Plusieurs intervalles de changements pendant l'écriture bloquée.
      for (var index = 0; index < 3; index++) {
        persister.schedule();
        await tester.pump(const Duration(seconds: 3));
        persister.flush();
      }

      expect(
        saver.started,
        1,
        reason: 'aucune écriture ne démarre avant la fin de la précédente',
      );

      saver.completeFirst();
      await tester.pump();

      expect(saver.started, 2, reason: 'une seule écriture de rattrapage');
      saver.completeAll();
      await tester.pump();
    });

    testWidgets('la sauvegarde suivante porte le dernier état', (tester) async {
      final saver = _GatedSaver();
      final persister = _persister(saver, () => saver.live);
      addTearDown(persister.dispose);
      // L'écran libère les écritures une fois l'historique relu.
      persister.release();

      saver.live = <ChatConversation>[_conversation(1, 'un')];
      persister.flush();

      // Les états intermédiaires se succèdent pendant l'écriture bloquée.
      for (final content in <String>['deux', 'trois', 'quatre']) {
        saver.live = <ChatConversation>[_conversation(1, content)];
        persister.flush();
      }

      saver.completeFirst();
      await tester.pump();
      saver.completeAll();
      await tester.pump();

      expect(saver.written, hasLength(2));
      expect(saver.written.first.single.messages.single.content, 'un');
      expect(
        saver.written.last.single.messages.single.content,
        'quatre',
        reason: 'les états intermédiaires ne sont pas rejoués',
      );
    });

    testWidgets('un fil supprimé pendant l’attente ne revient pas', (
      tester,
    ) async {
      final saver = _GatedSaver();
      final persister = _persister(saver, () => saver.live);
      addTearDown(persister.dispose);
      // L'écran libère les écritures une fois l'historique relu.
      persister.release();

      saver.live = <ChatConversation>[
        _conversation(1, 'bonjour'),
        _conversation(2, 'salut'),
      ];
      persister.flush();

      // Suppression alors que la première écriture n'est pas revenue.
      saver.live = <ChatConversation>[_conversation(2, 'salut')];
      persister.flush();

      saver.completeFirst();
      await tester.pump();
      saver.completeAll();
      await tester.pump();

      expect(saver.written.last.map((conversation) => conversation.id), <int>[
        2,
      ]);
    });

    testWidgets('le streaming garde sa cadence après une écriture', (
      tester,
    ) async {
      final saver = _GatedSaver()..autoComplete = true;
      final persister = _persister(saver, () => saver.live);
      addTearDown(persister.dispose);
      // L'écran libère les écritures une fois l'historique relu.
      persister.release();

      // Dix secondes de fragments à 20 ms, avec un stockage instantané : la
      // reprise après écriture ne doit pas enchaîner les sauvegardes.
      for (var index = 0; index < 500; index++) {
        persister.schedule();
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(saver.started, lessThanOrEqualTo(6));
      expect(saver.started, greaterThan(0));
    });

    testWidgets('la fermeture conserve ce qui a changé pendant l’écriture', (
      tester,
    ) async {
      final saver = _GatedSaver();
      final persister = _persister(saver, () => saver.live);

      saver.live = <ChatConversation>[_conversation(1, 'avant')];
      persister.flush();

      // Des fragments arrivent, puis l'écran se ferme, écriture toujours en
      // cours : c'est la dernière chance de les conserver.
      saver.live = <ChatConversation>[_conversation(1, 'après')];
      persister.schedule();
      persister.dispose();

      expect(saver.started, 1);

      saver.completeFirst();
      await tester.pump();
      saver.completeAll();
      await tester.pump();

      expect(saver.written, hasLength(2));
      expect(saver.written.last.single.messages.single.content, 'après');
    });

    testWidgets('la fermeture refuse les demandes qui suivent', (tester) async {
      final saver = _GatedSaver()..autoComplete = true;
      final persister = _persister(saver, () => saver.live);

      persister.schedule();
      persister.dispose();
      await tester.pump();
      final afterDispose = saver.started;

      persister.schedule();
      persister.flush();
      await tester.pump(const Duration(seconds: 5));

      expect(saver.started, afterDispose);
    });

    testWidgets('un échec n’empêche pas les sauvegardes suivantes', (
      tester,
    ) async {
      final reported = <Object>[];
      final saver = _GatedSaver()
        ..autoComplete = true
        ..failNext = true;
      final persister = ConversationPersister(
        save: saver.save,
        snapshot: () => saver.live,
        interval: const Duration(seconds: 2),
        onError: reported.add,
      );
      addTearDown(persister.dispose);
      // L'écran libère les écritures une fois l'historique relu.
      persister.release();

      saver.live = <ChatConversation>[_conversation(1, 'perdu')];
      persister.flush();
      await tester.pump();

      expect(reported, hasLength(1));
      expect(saver.written, isEmpty);

      saver.failNext = false;
      saver.live = <ChatConversation>[_conversation(1, 'conservé')];
      persister.flush();
      await tester.pump();

      expect(saver.written.single.single.messages.single.content, 'conservé');
      expect(
        tester.takeException(),
        isNull,
        reason: 'aucune erreur asynchrone',
      );
    });

    testWidgets('un échec pendant une écriture bloquée n’en perd aucune', (
      tester,
    ) async {
      final reported = <Object>[];
      final saver = _GatedSaver()..failNext = true;
      final persister = ConversationPersister(
        save: saver.save,
        snapshot: () => saver.live,
        interval: const Duration(seconds: 2),
        onError: reported.add,
      );
      addTearDown(persister.dispose);
      // L'écran libère les écritures une fois l'historique relu.
      persister.release();

      persister.flush();
      saver.live = <ChatConversation>[_conversation(1, 'après l’échec')];
      persister.flush();

      saver.failNext = false;
      saver.completeFirst();
      await tester.pump();
      saver.completeAll();
      await tester.pump();

      expect(reported, hasLength(1));
      expect(
        saver.written.single.single.messages.single.content,
        'après l’échec',
        reason: 'la demande faite pendant l’échec n’est pas perdue',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('échec d’enregistrement', () {
    testWidgets('l’échec est signalé une fois, pas à chaque fragment', (
      tester,
    ) async {
      final reported = <Object>[];
      var fail = true;
      final persister = ConversationPersister(
        save: (List<ChatConversation> conversations) async {
          if (fail) {
            throw const FileSystemException('disque plein');
          }
        },
        snapshot: () => <ChatConversation>[_conversation(1, 'x')],
        interval: const Duration(seconds: 2),
        onError: reported.add,
      );
      addTearDown(persister.dispose);
      // L'écran libère les écritures une fois l'historique relu.
      persister.release();

      for (var index = 0; index < 5; index++) {
        persister.flush();
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(reported, hasLength(1), reason: 'un seul avertissement');

      // Le disque revient : l'avertissement se réarme pour la prochaine fois.
      fail = false;
      persister.flush();
      await tester.pump(const Duration(milliseconds: 10));
      fail = true;
      persister.flush();
      await tester.pump(const Duration(milliseconds: 10));

      expect(reported, hasLength(2));
    });

    testWidgets('la file continue de servir après un échec', (tester) async {
      final written = <String>[];
      var fail = true;
      final persister = ConversationPersister(
        save: (List<ChatConversation> conversations) async {
          if (fail) {
            throw const FileSystemException('disque plein');
          }
          written.add(conversations.single.messages.single.content);
        },
        snapshot: () => <ChatConversation>[_conversation(1, 'après')],
        interval: const Duration(seconds: 2),
        onError: (_) {},
      );
      addTearDown(persister.dispose);
      // L'écran libère les écritures une fois l'historique relu.
      persister.release();

      persister.flush();
      await tester.pump(const Duration(milliseconds: 10));
      fail = false;
      persister.flush();
      await tester.pump(const Duration(milliseconds: 10));

      expect(written, <String>['après']);
    });
  });

  group('ConversationStore.save', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('foxllm-store-test');
    });

    tearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    test('un échec d’écriture remonte à l’appelant', () async {
      // Dossier supprimé : l'écriture du fichier temporaire échoue.
      final store = ConversationStore(
        applicationSupportDirectory: () async =>
            Directory('${directory.path}/absent'),
      );

      await expectLater(
        store.save(<ChatConversation>[_conversation(1, 'perdu')]),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('la sauvegarde suivante aboutit malgré l’échec précédent', () async {
      var useMissingDirectory = true;
      final store = ConversationStore(
        applicationSupportDirectory: () async => useMissingDirectory
            ? Directory('${directory.path}/absent')
            : directory,
      );

      await expectLater(
        store.save(<ChatConversation>[_conversation(1, 'perdu')]),
        throwsA(isA<FileSystemException>()),
      );

      useMissingDirectory = false;
      await expectLater(
        store.save(<ChatConversation>[_conversation(2, 'conservé')]),
        completes,
      );

      final reloaded = await store.load();
      expect(reloaded.single.id, 2);
      expect(reloaded.single.messages.single.content, 'conservé');
    });
  });
}

ConversationPersister _persister(
  _GatedSaver saver,
  List<ChatConversation> Function() snapshot,
) {
  return ConversationPersister(
    save: saver.save,
    snapshot: snapshot,
    interval: const Duration(seconds: 2),
    onError: (_) {},
  )..release(); // L'écran libère les écritures une fois l'historique relu.
}

/// Sauvegarde dont la fin est commandée, pour tenir une écriture ouverte.
class _GatedSaver {
  final List<Completer<void>> _gates = <Completer<void>>[];

  /// États réellement écrits, dans l'ordre.
  final List<List<ChatConversation>> written = <List<ChatConversation>>[];

  /// État courant, que le persister lira au moment d'écrire.
  List<ChatConversation> live = <ChatConversation>[_conversation(1, 'x')];

  /// Nombre d'écritures démarrées : la mesure qui compte ici.
  int started = 0;

  /// Termine chaque écriture sans attendre d'ordre.
  bool autoComplete = false;

  /// Fait échouer la prochaine écriture.
  bool failNext = false;

  Future<void> save(List<ChatConversation> conversations) async {
    started++;
    final failing = failNext;
    if (!autoComplete) {
      final gate = Completer<void>();
      _gates.add(gate);
      await gate.future;
    }
    if (failing) {
      throw const FileSystemException('disque plein');
    }
    written.add(conversations);
  }

  /// Libère la plus ancienne écriture encore ouverte.
  void completeFirst() {
    for (final gate in _gates) {
      if (!gate.isCompleted) {
        gate.complete();
        return;
      }
    }
  }

  void completeAll() {
    for (final gate in _gates) {
      if (!gate.isCompleted) {
        gate.complete();
      }
    }
  }
}
