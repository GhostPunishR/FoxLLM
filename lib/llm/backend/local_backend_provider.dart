// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:foxllm/llm/backend/local_llm_backend.dart';

final localLlmBackendProvider = Provider<LocalLlmBackend>((ref) {
  final backend = LocalLlmBackend();
  ref.onDispose(() {
    unawaited(backend.dispose());
  });
  return backend;
});
