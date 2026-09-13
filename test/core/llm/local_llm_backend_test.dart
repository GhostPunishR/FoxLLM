// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/llm/local_llm_backend.dart';
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
}
