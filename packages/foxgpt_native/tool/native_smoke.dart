// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:foxgpt_native/foxgpt_native.dart';

Future<void> main() async {
  final engine = FoxGptNativeEngine();

  try {
    final version = engine.version;
    if (!version.startsWith('foxgpt-native/0.3.0')) {
      throw StateError('Unexpected native engine version: $version');
    }

    if (engine.isModelLoaded || engine.modelInfo != null) {
      throw StateError('A new native engine must not have a model loaded.');
    }

    const missingModel = '/definitely/missing/foxgpt-smoke.gguf';
    if (engine.loadModel(missingModel)) {
      throw StateError('Loading a missing model unexpectedly succeeded.');
    }

    if (engine.lastError.isEmpty) {
      throw StateError('A failed model load must expose a native error.');
    }

    engine.unloadModel();
  } finally {
    engine.dispose();
  }

  final worker = await FoxGptNativeWorker.start();
  try {
    if (!worker.version.startsWith('foxgpt-native/0.3.0')) {
      throw StateError('Unexpected worker native version: ${worker.version}');
    }

    if (worker.isModelLoaded || worker.modelInfo != null) {
      throw StateError('A new native worker must not have a model loaded.');
    }

    worker.stop();

    var loadFailed = false;
    try {
      await worker.loadModel('/definitely/missing/foxgpt-worker-smoke.gguf');
    } on StateError {
      loadFailed = true;
    }
    if (!loadFailed) {
      throw StateError('Worker unexpectedly loaded a missing model.');
    }

    var generationFailed = false;
    try {
      await worker.generate(prompt: 'FFI worker smoke').drain<void>();
    } on StateError {
      generationFailed = true;
    }
    if (!generationFailed) {
      throw StateError('Worker unexpectedly generated without a model.');
    }
    if (worker.lastGenerationStats != null) {
      throw StateError('A failed generation must not publish success stats.');
    }

    await worker.unloadModel();
  } finally {
    await worker.dispose();
  }

  await worker.dispose();
  worker.stop();

  var disposedAccessRejected = false;
  try {
    final version = worker.version;
    if (version.isNotEmpty) {
      disposedAccessRejected = false;
    }
  } on StateError {
    disposedAccessRejected = true;
  }
  if (!disposedAccessRejected) {
    throw StateError('Disposed worker unexpectedly exposed its version.');
  }

  var disposedGenerationRejected = false;
  try {
    await worker.generate(prompt: 'disposed worker smoke').drain<void>();
  } on StateError {
    disposedGenerationRejected = true;
  }
  if (!disposedGenerationRejected) {
    throw StateError('Disposed worker unexpectedly accepted a generation.');
  }

  stdout.writeln('FoxGPT native worker smoke test passed.');
}
