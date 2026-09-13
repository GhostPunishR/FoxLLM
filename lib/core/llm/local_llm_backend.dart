import 'package:foxgpt_native/foxgpt_native.dart';

import 'chat_message.dart';
import 'generation_settings.dart';
import 'llm_backend.dart';

class LocalLlmBackend implements LlmBackend {
  LocalLlmBackend({Future<FoxGptNativeWorker>? worker})
    : _worker = worker ?? FoxGptNativeWorker.start();

  final Future<FoxGptNativeWorker> _worker;
  String? _loadedModelPath;
  String? _restorableModelPath;
  Future<void>? _restoring;

  @override
  String get id => 'local';

  @override
  String get displayName => 'Modèle local';

  String? get loadedModelPath => _loadedModelPath;

  /// Modèle utilisé lors de la session précédente, à recharger au besoin.
  String? get restorableModelPath => _restorableModelPath;

  /// Déclare un modèle à remettre en place sans le charger tout de suite :
  /// ouvrir un GGUF coûte plusieurs secondes et beaucoup de mémoire, ce qui
  /// retarderait l'affichage du chat.
  void markRestorable(String? path) {
    if (_loadedModelPath == null) {
      _restorableModelPath = path;
    }
  }

  /// Recharge le modèle mémorisé si aucun n'est chargé.
  ///
  /// Les appels concurrents partagent le même chargement, pour ne pas ouvrir
  /// deux fois le même GGUF.
  Future<void> restoreModelIfNeeded() {
    if (_loadedModelPath != null) {
      return Future<void>.value();
    }
    final path = _restorableModelPath;
    if (path == null) {
      return Future<void>.value();
    }
    return _restoring ??= loadModel(path).whenComplete(() {
      _restoring = null;
    });
  }

  Future<String> get nativeVersion async => (await _worker).version;

  Future<bool> get isModelLoaded async => (await _worker).isModelLoaded;

  Future<FoxGptModelInfo?> get modelInfo async => (await _worker).modelInfo;

  Future<FoxGptGenerationStats?> get lastGenerationStats async =>
      (await _worker).lastGenerationStats;

  Future<void> loadModel(String path) async {
    try {
      await (await _worker).loadModel(path);
      _loadedModelPath = path;
      _restorableModelPath = path;
    } catch (_) {
      _loadedModelPath = null;
      // Un modèle qui ne s'ouvre plus ne doit pas être retenté à chaque envoi.
      _restorableModelPath = null;
      rethrow;
    }
  }

  Future<void> unloadModel() async {
    await (await _worker).unloadModel();
    _loadedModelPath = null;
    _restorableModelPath = null;
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
    final FoxGptNativeWorker worker;
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
