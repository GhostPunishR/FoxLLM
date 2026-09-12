import 'package:foxgpt_native/foxgpt_native.dart';

import 'chat_message.dart';
import 'generation_settings.dart';
import 'llm_backend.dart';

class LocalLlmBackend implements LlmBackend {
  LocalLlmBackend({FoxGptNativeEngine? engine})
    : _engine = engine ?? FoxGptNativeEngine();

  final FoxGptNativeEngine _engine;

  @override
  String get id => 'local';

  @override
  String get displayName => 'Modèle local';

  String get nativeVersion => _engine.version;

  Future<void> loadModel(String path) async {
    final loaded = _engine.loadModel(path);
    if (!loaded) {
      throw StateError(_engine.lastError);
    }
  }

  @override
  Stream<String> generate({
    required List<ChatMessage> messages,
    GenerationSettings settings = const GenerationSettings(),
  }) async* {
    final prompt = _buildPrompt(messages);
    yield _engine.generate(prompt);
  }

  @override
  Future<void> stop() async {
    _engine.stop();
  }

  @override
  Future<void> dispose() async {
    _engine.dispose();
  }

  String _buildPrompt(List<ChatMessage> messages) {
    final buffer = StringBuffer();
    for (final message in messages) {
      buffer
        ..write('<|${message.role.name}|>\n')
        ..writeln(message.content);
    }
    buffer.write('<|assistant|>\n');
    return buffer.toString();
  }
}
