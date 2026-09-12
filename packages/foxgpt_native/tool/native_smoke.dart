import 'dart:io';

import 'package:foxgpt_native/foxgpt_native.dart';

void main() {
  final engine = FoxGptNativeEngine();

  try {
    final version = engine.version;
    if (!version.startsWith('foxgpt-native/0.2.0')) {
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

    stdout.writeln('FoxGPT native smoke test passed: $version');
  } finally {
    engine.dispose();
  }
}
