import 'chat_message.dart';
import 'generation_settings.dart';

abstract interface class LlmBackend {
  String get id;

  String get displayName;

  Stream<String> generate({
    required List<ChatMessage> messages,
    GenerationSettings settings = const GenerationSettings(),
  });

  Future<void> stop();

  Future<void> dispose();
}
