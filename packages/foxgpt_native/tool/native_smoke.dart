import 'package:foxgpt_native/foxgpt_native.dart';

void main() {
  final engine = FoxGptNativeEngine();

  try {
    final version = engine.version;
    if (!version.startsWith('foxgpt-native/')) {
      throw StateError('Unexpected native engine version: $version');
    }

    print('FoxGPT native smoke test passed: $version');
  } finally {
    engine.dispose();
  }
}
