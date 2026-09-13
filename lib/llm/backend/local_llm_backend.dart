// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:foxllm_native/foxllm_native.dart';

import 'package:foxllm/llm/backend/llm_backend.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/generation_settings.dart';

class LocalLlmBackend implements LlmBackend {
  LocalLlmBackend({Future<FoxLlmNativeWorker>? worker})
    : _worker = worker ?? FoxLlmNativeWorker.start();

  final Future<FoxLlmNativeWorker> _worker;
  String? _loadedModelPath;

  @override
  String get id => 'local';

  @override
  String get displayName => 'Modèle local';

  String? get loadedModelPath => _loadedModelPath;

  Future<String> get nativeVersion async => (await _worker).version;

  Future<bool> get isModelLoaded async => (await _worker).isModelLoaded;

  Future<FoxLlmModelInfo?> get modelInfo async => (await _worker).modelInfo;

  Future<FoxLlmGenerationStats?> get lastGenerationStats async =>
      (await _worker).lastGenerationStats;

  Future<void> loadModel(String path) async {
    try {
      await (await _worker).loadModel(path);
      _loadedModelPath = path;
    } catch (_) {
      _loadedModelPath = null;
      rethrow;
    }
  }

  Future<void> unloadModel() async {
    await (await _worker).unloadModel();
    _loadedModelPath = null;
  }

  @override
  Stream<String> generate({
    required List<ChatMessage> messages,
    GenerationSettings settings = const GenerationSettings(),
  }) async* {
    final worker = await _worker;
    final prompt = _buildPrompt(messages);
    yield* worker.generate(
      prompt: prompt,
      temperature: settings.temperature,
      topP: settings.topP,
      maxTokens: settings.maxTokens,
    );
  }

  @override
  Future<void> stop() async {
    (await _worker).stop();
  }

  @override
  Future<void> dispose() async {
    final FoxLlmNativeWorker worker;
    try {
      worker = await _worker;
    } catch (_) {
      // Startup errors are surfaced by the operation that awaited the worker.
      // Cleanup must remain safe when the app is already being disposed.
      return;
    }

    _loadedModelPath = null;
    await worker.dispose();
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
