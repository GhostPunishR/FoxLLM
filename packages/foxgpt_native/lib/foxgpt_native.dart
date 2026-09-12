@DefaultAsset('package:foxgpt_native/foxgpt_native.dart')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

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

class FoxGptNativeEngine {
  FoxGptNativeEngine() : _handle = _engineCreate() {
    if (_handle == nullptr) {
      throw StateError('Unable to create FoxGPT native engine.');
    }
  }

  Pointer<Void> _handle;

  bool get isDisposed => _handle == nullptr;

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
