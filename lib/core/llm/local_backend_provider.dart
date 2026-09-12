import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_llm_backend.dart';

final localLlmBackendProvider = Provider<LocalLlmBackend>((ref) {
  final backend = LocalLlmBackend();
  ref.onDispose(() {
    unawaited(backend.dispose());
  });
  return backend;
});
