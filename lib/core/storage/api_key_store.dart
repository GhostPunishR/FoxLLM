// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:foxllm/llm/personal_api/provider_config.dart';

class ApiKeyStore {
  ApiKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final Map<String, String> _sessionKeys = <String, String>{};

  String _storageKey(String providerId) =>
      'foxllm.provider.$providerId.api_key';

  Future<void> save({
    required String providerId,
    required String apiKey,
    required ApiKeyPersistence persistence,
  }) async {
    if (persistence == ApiKeyPersistence.session) {
      _sessionKeys[providerId] = apiKey;
      await _storage.delete(key: _storageKey(providerId));
      return;
    }

    _sessionKeys.remove(providerId);
    await _storage.write(key: _storageKey(providerId), value: apiKey);
  }

  Future<String?> read({
    required String providerId,
    required ApiKeyPersistence persistence,
  }) async {
    if (persistence == ApiKeyPersistence.session) {
      return _sessionKeys[providerId];
    }

    return _storage.read(key: _storageKey(providerId));
  }

  Future<void> delete(String providerId) async {
    _sessionKeys.remove(providerId);
    await _storage.delete(key: _storageKey(providerId));
  }
}
