// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/llm/backend/local_llm_backend.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm_native/foxllm_native.dart';

void main() {
  group('LocalLlmBackend worker lifecycle', () {
    test('nativeVersion surfaces a worker startup failure', () async {
      final worker = Completer<FoxLlmNativeWorker>();
      final backend = LocalLlmBackend(worker: worker.future);
      final expectation = expectLater(
        backend.nativeVersion,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'worker startup failed',
          ),
        ),
      );

      worker.completeError(StateError('worker startup failed'));

      await expectation;
    });

    test('dispose stays safe when worker startup failed', () async {
      final worker = Completer<FoxLlmNativeWorker>();
      final backend = LocalLlmBackend(worker: worker.future);
      final disposeFuture = backend.dispose();

      worker.completeError(StateError('worker startup failed'));

      await expectLater(disposeFuture, completes);
    });
  });

  group('réponse écourtée', () {
    /// Fait générer une réponse entière et rend le motif retenu ensuite.
    Future<String?> reasonAfter(
      FoxLlmStopReason stopReason, {
      String text = 'une réponse',
    }) async {
      final worker = _FakeWorker(
        chunks: <String>[text],
        stopReason: stopReason,
      );
      final backend = LocalLlmBackend(
        worker: Future<FoxLlmNativeWorker>.value(worker),
      );
      await backend.generate(messages: _question).toList();
      return backend.incompleteReason;
    }

    test('un plafond de jetons atteint se dit comme sur le réseau', () async {
      // `length` est la clé qu'emploient les API distantes : le chat sait
      // déjà l'expliquer, et l'arrêt est le même.
      expect(await reasonAfter(FoxLlmStopReason.tokenLimit), 'length');
    });

    test('une fenêtre pleine se distingue du plafond demandé', () async {
      // Le remède diffère : relever la limite n'y changerait rien.
      expect(
        await reasonAfter(FoxLlmStopReason.contextLimit),
        'context_length',
      );
    });

    test('une réponse achevée n’a aucun motif', () async {
      expect(await reasonAfter(FoxLlmStopReason.endOfText), isNull);
    });

    test('un arrêt demandé n’est pas une réponse écourtée', () async {
      // Le chat le tient déjà pour ce qu'il est ; le redire ici le ferait
      // passer pour une limite atteinte.
      expect(await reasonAfter(FoxLlmStopReason.cancelled), isNull);
    });

    test('le motif du tour précédent ne déborde pas sur le suivant', () async {
      final worker = _FakeWorker(
        chunks: <String>['coupée'],
        stopReason: FoxLlmStopReason.tokenLimit,
      );
      final backend = LocalLlmBackend(
        worker: Future<FoxLlmNativeWorker>.value(worker),
      );

      await backend.generate(messages: _question).toList();
      expect(backend.incompleteReason, 'length');

      worker.stopReason = FoxLlmStopReason.endOfText;
      await backend.generate(messages: _question).toList();
      expect(backend.incompleteReason, isNull);
    });

    test('une génération en erreur ne laisse aucun motif', () async {
      // Une panne est un échec, pas une réponse partielle : le chat a son
      // propre traitement, et un motif ici le contredirait.
      final worker = _FakeWorker(
        chunks: const <String>[],
        stopReason: FoxLlmStopReason.tokenLimit,
        failure: StateError('le moteur a lâché'),
      );
      final backend = LocalLlmBackend(
        worker: Future<FoxLlmNativeWorker>.value(worker),
      );

      await expectLater(
        backend.generate(messages: _question).toList(),
        throwsA(isA<StateError>()),
      );
      expect(backend.incompleteReason, isNull);
    });
  });
}

final _question = <ChatMessage>[ChatMessage.user('une question')];

/// Un ouvrier natif de façade : ni isolat, ni modèle, ni bibliothèque.
///
/// Seuls le gabarit, le flux et le relevé final comptent ici. Le reste passe
/// par `noSuchMethod` plutôt que d'être recopié membre à membre : ce banc
/// n'appelle rien d'autre, et l'y obliger le rendrait illisible.
class _FakeWorker implements FoxLlmNativeWorker {
  _FakeWorker({required this.chunks, required this.stopReason, this.failure});

  final List<String> chunks;
  FoxLlmStopReason stopReason;
  final Object? failure;

  @override
  Future<String> applyChatTemplate(
    List<FoxLlmChatMessage> messages, {
    bool addAssistant = true,
  }) async => 'prompt';

  @override
  Stream<String> generate({
    required String prompt,
    double temperature = 0.7,
    double topP = 0.9,
    int maxTokens = 512,
  }) async* {
    for (final chunk in chunks) {
      yield chunk;
    }
    if (failure != null) {
      throw failure!;
    }
  }

  /// Relevé du tour qui vient de finir, comme le vrai ouvrier le pose avant
  /// de fermer son flux.
  @override
  FoxLlmGenerationStats? get lastGenerationStats => FoxLlmGenerationStats(
    generatedTokens: chunks.length,
    elapsed: const Duration(seconds: 1),
    stopReason: stopReason,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
