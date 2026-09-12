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

    await worker.unloadModel();
  } finally {
    await worker.dispose();
  }

  stdout.writeln('FoxGPT native worker smoke test passed.');
}
