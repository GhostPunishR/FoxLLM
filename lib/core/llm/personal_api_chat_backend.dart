import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:foxgpt_native/foxgpt_native.dart';

import 'chat_message.dart';
import 'generation_settings.dart';
import 'local_backend_provider.dart';
import 'local_llm_backend.dart';
import 'openai_compatible_backend.dart';
import 'personal_api_settings.dart';
import 'personal_api_settings_provider.dart';

final personalApiChatBackendProvider = Provider<LocalLlmBackend?>((ref) {
  final settings = ref.watch(personalApiSettingsProvider).value;
  if (settings == null || !settings.useInChat || !settings.isConfigured) {
    return null;
  }

  final backend = PersonalApiChatBackend(
    settings: settings,
    remoteBackend: OpenAiCompatibleBackend(
      provider: settings.toProviderConfig(),
      keyStore: ref.read(apiKeyStoreProvider),
    ),
    localBackend: ref.read(localLlmBackendProvider),
  );
  ref.onDispose(() {
    unawaited(backend.dispose());
  });
  return backend;
});

class PersonalApiChatBackend implements LocalLlmBackend {
  PersonalApiChatBackend({
    required PersonalApiSettings settings,
    required OpenAiCompatibleBackend remoteBackend,
    required LocalLlmBackend localBackend,
  })  : _settings = settings,
        _remoteBackend = remoteBackend,
        _localBackend = localBackend;

  final PersonalApiSettings _settings;
  final OpenAiCompatibleBackend _remoteBackend;
  final LocalLlmBackend _localBackend;

  @override
  String get id => personalApiProviderId;

  @override
  String get displayName => 'API personnelle';

  @override
  String? get loadedModelPath => 'api://${_settings.model}';

  @override
  Future<String> get nativeVersion => Future<String>.value('API distante');

  @override
  Future<bool> get isModelLoaded => Future<bool>.value(true);

  @override
  Future<FoxGptModelInfo?> get modelInfo => _localBackend.modelInfo;

  @override
  Future<FoxGptGenerationStats?> get lastGenerationStats =>
      _localBackend.lastGenerationStats;

  @override
  Future<void> loadModel(String path) => _localBackend.loadModel(path);

  @override
  Future<void> unloadModel() => _localBackend.unloadModel();

  @override
  Stream<String> generate({
    required List<ChatMessage> messages,
    GenerationSettings settings = const GenerationSettings(),
  }) {
    return _remoteBackend.generate(messages: messages, settings: settings);
  }

  @override
  Future<void> stop() => _remoteBackend.stop();

  @override
  Future<void> dispose() => _remoteBackend.dispose();
}
