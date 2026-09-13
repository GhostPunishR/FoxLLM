// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:foxllm_native/foxllm_native.dart';

import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm/llm/backend/llm_backend.dart';
import 'package:foxllm/llm/backend/local_backend_provider.dart';
import 'package:foxllm/llm/backend/local_llm_backend.dart';
import 'package:foxllm/llm/personal_api/personal_api_settings.dart';
import 'package:foxllm/llm/personal_api/personal_api_settings_provider.dart';

final personalApiChatBackendProvider = Provider<LocalLlmBackend?>((ref) {
  final settings = ref.watch(personalApiSettingsProvider).value;
  if (settings == null || !settings.useInChat || !settings.isConfigured) {
    return null;
  }

  final backend = PersonalApiChatBackend(
    settings: settings,
    remoteBackend: createPersonalApiRemoteBackend(
      settings: settings,
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
    required LlmBackend remoteBackend,
    required LocalLlmBackend localBackend,
  }) : _settings = settings,
       _remoteBackend = remoteBackend,
       _localBackend = localBackend;

  final PersonalApiSettings _settings;
  final LlmBackend _remoteBackend;
  final LocalLlmBackend _localBackend;

  @override
  String get id => personalApiProviderId;

  @override
  String get displayName =>
      'API personnelle · ${_settings.provider.displayName}';

  /// Vrai si le fournisseur configuré sait consulter le web.
  ///
  /// Gemini et l'API Responses d'OpenAI ont chacun un outil de recherche
  /// intégré ; les fournisseurs qui se contentent d'imiter
  /// `chat/completions` n'en ont aucun.
  bool get supportsWebSearch => _settings.provider.supportsWebSearch;

  @override
  String? get loadedModelPath =>
      'api://${_settings.provider.id}/${_settings.model}';

  @override
  Future<String> get nativeVersion => Future<String>.value('API distante');

  @override
  Future<bool> get isModelLoaded => Future<bool>.value(true);

  @override
  Future<FoxLlmModelInfo?> get modelInfo => _localBackend.modelInfo;

  @override
  Future<FoxLlmGenerationStats?> get lastGenerationStats =>
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
