// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

@DefaultAsset('package:foxgpt_native/foxgpt_native.dart')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _TokenCallbackNative =
    Void Function(Pointer<Uint8>, Int32, Pointer<Void>);

@Native<Pointer<Void> Function()>(symbol: 'foxgpt_engine_create')
external Pointer<Void> _engineCreate();

@Native<Void Function(Pointer<Void>)>(symbol: 'foxgpt_engine_destroy')
external void _engineDestroy(Pointer<Void> engine);

@Native<Int32 Function(Pointer<Void>, Pointer<Utf8>)>(
  symbol: 'foxgpt_engine_load_model',
)
external int _engineLoadModel(Pointer<Void> engine, Pointer<Utf8> modelPath);

@Native<Void Function(Pointer<Void>)>(symbol: 'foxgpt_engine_unload_model')
external void _engineUnloadModel(Pointer<Void> engine);

@Native<Int32 Function(Pointer<Void>)>(symbol: 'foxgpt_engine_is_model_loaded')
external int _engineIsModelLoaded(Pointer<Void> engine);

@Native<Pointer<Utf8> Function(Pointer<Void>)>(
  symbol: 'foxgpt_engine_model_description',
)
external Pointer<Utf8> _engineModelDescription(Pointer<Void> engine);

@Native<Uint64 Function(Pointer<Void>)>(
  symbol: 'foxgpt_engine_model_size_bytes',
)
external int _engineModelSizeBytes(Pointer<Void> engine);

@Native<Int32 Function(Pointer<Void>)>(
  symbol: 'foxgpt_engine_model_context_size',
)
external int _engineModelContextSize(Pointer<Void> engine);

@Native<Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>(
  symbol: 'foxgpt_engine_generate',
)
external Pointer<Utf8> _engineGenerate(
  Pointer<Void> engine,
  Pointer<Utf8> prompt,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Float,
    Float,
    Int32,
    Pointer<NativeFunction<_TokenCallbackNative>>,
    Pointer<Void>,
  )
>(symbol: 'foxgpt_engine_generate_stream')
external int _engineGenerateStream(
  Pointer<Void> engine,
  Pointer<Utf8> prompt,
  double temperature,
  double topP,
  int maxTokens,
  Pointer<NativeFunction<_TokenCallbackNative>> callback,
  Pointer<Void> userData,
);

@Native<Void Function(Pointer<Void>)>(symbol: 'foxgpt_engine_reset_stop')
external void _engineResetStop(Pointer<Void> engine);

@Native<Void Function(Pointer<Void>)>(symbol: 'foxgpt_engine_stop')
external void _engineStop(Pointer<Void> engine);

@Native<Pointer<Utf8> Function(Pointer<Void>)>(
  symbol: 'foxgpt_engine_last_error',
)
external Pointer<Utf8> _engineLastError(Pointer<Void> engine);

@Native<Pointer<Utf8> Function()>(symbol: 'foxgpt_native_version')
external Pointer<Utf8> _nativeVersion();

@Native<Void Function(Pointer<Utf8>)>(symbol: 'foxgpt_string_free')
external void _stringFree(Pointer<Utf8> value);

class FoxGptModelInfo {
  const FoxGptModelInfo({
    required this.description,
    required this.sizeBytes,
    required this.contextSize,
  });

  final String description;
  final int sizeBytes;
  final int contextSize;
}

class FoxGptGenerationStats {
  const FoxGptGenerationStats({
    required this.generatedTokens,
    required this.elapsed,
  });

  final int generatedTokens;
  final Duration elapsed;

  double get tokensPerSecond {
    if (elapsed.inMicroseconds == 0) {
      return 0;
    }
    return generatedTokens *
        Duration.microsecondsPerSecond /
        elapsed.inMicroseconds;
  }
}

class FoxGptNativeEngine {
  FoxGptNativeEngine() : _handle = _engineCreate() {
    if (_handle == nullptr) {
      throw StateError('Unable to create FoxGPT native engine.');
    }
  }

  Pointer<Void> _handle;

  bool get isDisposed => _handle == nullptr;

  int get _handleAddress => _handle.address;

  String get version => _nativeVersion().toDartString();

  bool get isModelLoaded {
    _ensureAlive();
    return _engineIsModelLoaded(_handle) == 1;
  }

  FoxGptModelInfo? get modelInfo {
    _ensureAlive();
    if (!isModelLoaded) {
      return null;
    }

    return FoxGptModelInfo(
      description: _engineModelDescription(_handle).toDartString(),
      sizeBytes: _engineModelSizeBytes(_handle),
      contextSize: _engineModelContextSize(_handle),
    );
  }

  String get lastError {
    _ensureAlive();
    return _engineLastError(_handle).toDartString();
  }

  bool loadModel(String path) {
    _ensureAlive();
    final nativePath = path.toNativeUtf8();
    try {
      return _engineLoadModel(_handle, nativePath) == 1;
    } finally {
      calloc.free(nativePath);
    }
  }

  void unloadModel() {
    _ensureAlive();
    _engineUnloadModel(_handle);
  }

  String generate(String prompt) {
    _ensureAlive();
    final nativePrompt = prompt.toNativeUtf8();

    try {
      final result = _engineGenerate(_handle, nativePrompt);
      if (result == nullptr) {
        throw StateError(lastError);
      }

      try {
        return result.toDartString();
      } finally {
        _stringFree(result);
      }
    } finally {
      calloc.free(nativePrompt);
    }
  }

  void generateStream({
    required String prompt,
    required void Function(Uint8List bytes) onToken,
    double temperature = 0.7,
    double topP = 0.9,
    int maxTokens = 512,
  }) {
    _ensureAlive();
    final nativePrompt = prompt.toNativeUtf8();
    final callback = NativeCallable<_TokenCallbackNative>.isolateLocal((
      Pointer<Uint8> bytes,
      int length,
      Pointer<Void> userData,
    ) {
      if (length <= 0) {
        onToken(Uint8List(0));
        return;
      }
      onToken(Uint8List.fromList(bytes.asTypedList(length)));
    });

    try {
      final succeeded = _engineGenerateStream(
        _handle,
        nativePrompt,
        temperature,
        topP,
        maxTokens,
        callback.nativeFunction,
        nullptr,
      );
      if (succeeded != 1) {
        throw StateError(lastError);
      }
    } finally {
      callback.close();
      calloc.free(nativePrompt);
    }
  }

  void resetStop() {
    if (!isDisposed) {
      _engineResetStop(_handle);
    }
  }

  void stop() {
    if (!isDisposed) {
      _engineStop(_handle);
    }
  }

  void dispose() {
    if (isDisposed) {
      return;
    }
    _engineDestroy(_handle);
    _handle = nullptr;
  }

  void _ensureAlive() {
    if (isDisposed) {
      throw StateError('FoxGPT native engine is disposed.');
    }
  }
}

class FoxGptNativeWorker {
  FoxGptNativeWorker._();

  final Completer<void> _ready = Completer<void>();
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  final Map<int, StreamController<List<int>>> _generationStreams =
      <int, StreamController<List<int>>>{};

  late final ReceivePort _eventsPort;
  late final ReceivePort _errorsPort;
  late final ReceivePort _exitPort;
  StreamSubscription<dynamic>? _eventsSubscription;
  StreamSubscription<dynamic>? _errorsSubscription;
  StreamSubscription<dynamic>? _exitSubscription;
  Isolate? _isolate;
  SendPort? _commands;

  int _nextRequestId = 1;
  int _handleAddress = 0;
  int? _activeGenerationId;
  Completer<void>? _activeGenerationDone;
  bool _generationStopRequested = false;
  bool _disposing = false;
  bool _disposed = false;
  Object? _failure;
  String _version = '';
  FoxGptModelInfo? _modelInfo;
  FoxGptGenerationStats? _lastGenerationStats;

  static Future<FoxGptNativeWorker> start() async {
    final worker = FoxGptNativeWorker._();
    worker._eventsPort = ReceivePort();
    worker._errorsPort = ReceivePort();
    worker._exitPort = ReceivePort();

    worker._eventsSubscription = worker._eventsPort.listen(worker._handleEvent);
    worker._errorsSubscription = worker._errorsPort.listen(worker._handleError);
    worker._exitSubscription = worker._exitPort.listen(worker._handleExit);

    try {
      worker._isolate = await Isolate.spawn<SendPort>(
        _foxGptNativeWorkerMain,
        worker._eventsPort.sendPort,
        onError: worker._errorsPort.sendPort,
        onExit: worker._exitPort.sendPort,
        errorsAreFatal: true,
        debugName: 'FoxGPT native inference',
      );
      await worker._ready.future.timeout(const Duration(seconds: 15));
      return worker;
    } catch (_) {
      worker._isolate?.kill(priority: Isolate.immediate);
      await worker._closePorts();
      rethrow;
    }
  }

  String get version {
    _ensureUsable();
    return _version;
  }

  bool get isModelLoaded {
    _ensureUsable();
    return _modelInfo != null;
  }

  FoxGptModelInfo? get modelInfo {
    _ensureUsable();
    return _modelInfo;
  }

  FoxGptGenerationStats? get lastGenerationStats {
    _ensureUsable();
    return _lastGenerationStats;
  }

  Future<void> loadModel(String path) async {
    _ensureUsable();
    _ensureIdle('load a model');
    final value = await _request('load', <String, Object?>{'path': path});
    _modelInfo = _decodeModelInfo(value);
  }

  Future<void> unloadModel() async {
    _ensureUsable();
    _ensureIdle('unload the model');
    await _request('unload');
    _modelInfo = null;
  }

  Stream<String> generate({
    required String prompt,
    double temperature = 0.7,
    double topP = 0.9,
    int maxTokens = 512,
  }) {
    _ensureUsable();

    final requestId = _nextRequestId++;
    late final StreamController<List<int>> bytesController;
    bytesController = StreamController<List<int>>(
      onListen: () {
        final commands = _commands;
        if (_disposed || _disposing || _failure != null || commands == null) {
          bytesController.addError(
            StateError('FoxGPT native worker is unavailable.'),
          );
          unawaited(bytesController.close());
          return;
        }

        if (_activeGenerationId != null) {
          bytesController.addError(
            StateError('A local generation is already running.'),
          );
          unawaited(bytesController.close());
          return;
        }

        _activeGenerationId = requestId;
        _activeGenerationDone = Completer<void>();
        _generationStopRequested = false;
        _generationStreams[requestId] = bytesController;
        commands.send(<String, Object?>{
          'type': 'generate',
          'id': requestId,
          'prompt': prompt,
          'temperature': temperature,
          'topP': topP,
          'maxTokens': maxTokens,
        });
      },
      onCancel: () {
        if (_activeGenerationId == requestId) {
          stop();
        }
      },
    );

    return bytesController.stream.transform(
      const Utf8Decoder(allowMalformed: true),
    );
  }

  void stop() {
    if (_disposed ||
        _disposing ||
        _activeGenerationId == null ||
        _handleAddress == 0) {
      return;
    }

    _generationStopRequested = true;
    _engineStop(Pointer<Void>.fromAddress(_handleAddress));
  }

  Future<void> dispose() async {
    if (_disposed || _disposing) {
      return;
    }

    stop();
    _disposing = true;
    final activeGenerationDone = _activeGenerationDone;

    try {
      if (activeGenerationDone != null) {
        try {
          await activeGenerationDone.future;
        } catch (_) {
          // A worker failure is handled below by skipping the dispose request.
        }
      }

      if (_commands != null) {
        await _requestInternal('dispose');
      }
    } finally {
      _disposed = true;
      _disposing = false;
      _handleAddress = 0;
      _commands = null;
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      await _closePorts();
    }
  }

  Future<Object?> _request(
    String type, [
    Map<String, Object?> data = const <String, Object?>{},
  ]) {
    _ensureUsable();
    return _requestInternal(type, data);
  }

  Future<Object?> _requestInternal(
    String type, [
    Map<String, Object?> data = const <String, Object?>{},
  ]) {
    final commands = _commands;
    if (commands == null) {
      throw StateError('FoxGPT native worker is not ready.');
    }

    final requestId = _nextRequestId++;
    final completer = Completer<Object?>();
    _pending[requestId] = completer;
    commands.send(<String, Object?>{'type': type, 'id': requestId, ...data});
    return completer.future;
  }

  void _handleEvent(dynamic message) {
    if (message is! Map<Object?, Object?>) {
      return;
    }

    final type = message['type'];
    if (type == 'ready') {
      _commands = message['commands']! as SendPort;
      _handleAddress = message['handle']! as int;
      _version = message['version']! as String;
      if (!_ready.isCompleted) {
        _ready.complete();
      }
      return;
    }

    final requestId = message['id'];
    if (requestId is! int) {
      return;
    }

    switch (type) {
      case 'response':
        final completer = _pending.remove(requestId);
        if (completer == null || completer.isCompleted) {
          return;
        }
        final error = message['error'];
        if (error is String && error.isNotEmpty) {
          completer.completeError(StateError(error));
        } else {
          completer.complete(message['value']);
        }
      case 'generationStarted':
        if (_activeGenerationId == requestId &&
            _generationStopRequested &&
            _handleAddress != 0) {
          _engineStop(Pointer<Void>.fromAddress(_handleAddress));
        }
      case 'generationChunk':
        final controller = _generationStreams[requestId];
        final bytes = message['bytes'];
        if (controller != null && bytes is Uint8List && !controller.isClosed) {
          controller.add(bytes);
        }
      case 'generationDone':
        _lastGenerationStats = FoxGptGenerationStats(
          generatedTokens: message['tokens']! as int,
          elapsed: Duration(microseconds: message['elapsedMicros']! as int),
        );
        _finishGeneration(requestId);
      case 'generationError':
        final controller = _generationStreams[requestId];
        if (controller != null && !controller.isClosed) {
          controller.addError(StateError(message['error']! as String));
        }
        _finishGeneration(requestId);
    }
  }

  void _finishGeneration(int requestId) {
    final controller = _generationStreams.remove(requestId);
    if (controller != null && !controller.isClosed) {
      unawaited(controller.close());
    }
    if (_activeGenerationId == requestId) {
      _activeGenerationId = null;
      _generationStopRequested = false;
      final generationDone = _activeGenerationDone;
      _activeGenerationDone = null;
      if (generationDone != null && !generationDone.isCompleted) {
        generationDone.complete();
      }
    }
  }

  void _handleError(dynamic message) {
    final description = message is List<dynamic> && message.isNotEmpty
        ? message.first.toString()
        : message.toString();
    _failAll(StateError('FoxGPT native worker failed: $description'));
  }

  void _handleExit(dynamic _) {
    if (!_disposed) {
      _failAll(StateError('FoxGPT native worker exited unexpectedly.'));
    }
  }

  void _failAll(Object error) {
    _failure ??= error;
    _commands = null;
    _handleAddress = 0;

    if (!_ready.isCompleted) {
      _ready.completeError(error);
    }

    final pending = _pending.values.toList(growable: false);
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }

    final streams = _generationStreams.values.toList(growable: false);
    _generationStreams.clear();
    for (final controller in streams) {
      if (!controller.isClosed) {
        controller.addError(error);
        unawaited(controller.close());
      }
    }

    final generationDone = _activeGenerationDone;
    _activeGenerationDone = null;
    if (generationDone != null && !generationDone.isCompleted) {
      generationDone.completeError(error);
    }
    _activeGenerationId = null;
    _generationStopRequested = false;
  }

  Future<void> _closePorts() async {
    await _eventsSubscription?.cancel();
    await _errorsSubscription?.cancel();
    await _exitSubscription?.cancel();
    _eventsPort.close();
    _errorsPort.close();
    _exitPort.close();
  }

  void _ensureUsable() {
    if (_disposed || _disposing) {
      throw StateError('FoxGPT native worker is disposed.');
    }
    final failure = _failure;
    if (failure != null) {
      throw StateError('FoxGPT native worker is unavailable: $failure');
    }
  }

  void _ensureIdle(String action) {
    if (_activeGenerationId != null) {
      throw StateError('Cannot $action while a local generation is running.');
    }
  }
}

void _foxGptNativeWorkerMain(SendPort events) {
  final commands = ReceivePort();
  final engine = FoxGptNativeEngine();

  events.send(<String, Object?>{
    'type': 'ready',
    'commands': commands.sendPort,
    'handle': engine._handleAddress,
    'version': engine.version,
  });

  commands.listen((dynamic message) {
    if (message is! Map<Object?, Object?>) {
      return;
    }

    final type = message['type'];
    final requestId = message['id'];
    if (type is! String || requestId is! int) {
      return;
    }

    try {
      switch (type) {
        case 'load':
          final path = message['path']! as String;
          if (!engine.loadModel(path)) {
            throw StateError(engine.lastError);
          }
          events.send(<String, Object?>{
            'type': 'response',
            'id': requestId,
            'value': _encodeModelInfo(engine.modelInfo),
          });
        case 'unload':
          engine.unloadModel();
          events.send(<String, Object?>{'type': 'response', 'id': requestId});
        case 'generate':
          engine.resetStop();
          events.send(<String, Object?>{
            'type': 'generationStarted',
            'id': requestId,
          });

          final stopwatch = Stopwatch()..start();
          final generatedTokens = <int>[0];
          engine.generateStream(
            prompt: message['prompt']! as String,
            temperature: message['temperature']! as double,
            topP: message['topP']! as double,
            maxTokens: message['maxTokens']! as int,
            onToken: (Uint8List bytes) {
              generatedTokens[0]++;
              if (bytes.isNotEmpty) {
                events.send(<String, Object?>{
                  'type': 'generationChunk',
                  'id': requestId,
                  'bytes': bytes,
                });
              }
            },
          );
          stopwatch.stop();
          events.send(<String, Object?>{
            'type': 'generationDone',
            'id': requestId,
            'tokens': generatedTokens[0],
            'elapsedMicros': stopwatch.elapsedMicroseconds,
          });
        case 'dispose':
          engine.dispose();
          events.send(<String, Object?>{'type': 'response', 'id': requestId});
      }
    } catch (error) {
      if (type == 'generate') {
        events.send(<String, Object?>{
          'type': 'generationError',
          'id': requestId,
          'error': error.toString(),
        });
      } else {
        events.send(<String, Object?>{
          'type': 'response',
          'id': requestId,
          'error': error.toString(),
        });
      }
    }
  });
}

Map<String, Object?>? _encodeModelInfo(FoxGptModelInfo? info) {
  if (info == null) {
    return null;
  }
  return <String, Object?>{
    'description': info.description,
    'sizeBytes': info.sizeBytes,
    'contextSize': info.contextSize,
  };
}

FoxGptModelInfo? _decodeModelInfo(Object? value) {
  if (value is! Map<Object?, Object?>) {
    return null;
  }
  return FoxGptModelInfo(
    description: value['description']! as String,
    sizeBytes: value['sizeBytes']! as int,
    contextSize: value['contextSize']! as int,
  );
}
