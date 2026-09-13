// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:foxllm/core/storage/api_key_store.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/backend/gemini_backend.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm/llm/backend/llm_backend.dart';
import 'package:foxllm/llm/backend/openai_compatible_backend.dart';
import 'package:foxllm/llm/backend/openai_responses_backend.dart';
import 'package:foxllm/llm/personal_api/personal_api_provider.dart';
import 'package:foxllm/llm/personal_api/provider_config.dart';

const personalApiProviderId = 'personal-api';

class PersonalApiSettings {
  const PersonalApiSettings({
    this.providerId = 'openai',
    this.baseUrl = '',
    this.model = '',
    this.apiKeyPersistence = ApiKeyPersistence.device,
    this.useInChat = false,
    this.hasApiKey = false,
  });

  final String providerId;
  final String baseUrl;
  final String model;
  final ApiKeyPersistence apiKeyPersistence;
  final bool useInChat;
  final bool hasApiKey;

  PersonalApiProvider get provider => personalApiProviderById(providerId);

  String get effectiveBaseUrl => provider.resolveBaseUrl(baseUrl);

  bool get isConfigured =>
      effectiveBaseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty &&
      hasApiKey;

  ProviderConfig toProviderConfig() => ProviderConfig(
    id: personalApiProviderId,
    displayName: provider.displayName,
    baseUrl: effectiveBaseUrl,
    model: model.trim(),
    apiKeyPersistence: apiKeyPersistence,
  );

  PersonalApiSettings copyWith({
    String? providerId,
    String? baseUrl,
    String? model,
    ApiKeyPersistence? apiKeyPersistence,
    bool? useInChat,
    bool? hasApiKey,
  }) {
    return PersonalApiSettings(
      providerId: providerId ?? this.providerId,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      apiKeyPersistence: apiKeyPersistence ?? this.apiKeyPersistence,
      useInChat: useInChat ?? this.useInChat,
      hasApiKey: hasApiKey ?? this.hasApiKey,
    );
  }
}

class PersonalApiSettingsStore {
  PersonalApiSettingsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? FlutterSecureStorage();

  static const _providerKey = 'foxllm.personal_api.provider';
  static const _baseUrlKey = 'foxllm.personal_api.base_url';
  static const _modelKey = 'foxllm.personal_api.model';
  static const _persistenceKey = 'foxllm.personal_api.persistence';
  static const _useInChatKey = 'foxllm.personal_api.use_in_chat';

  final FlutterSecureStorage _storage;

  Future<PersonalApiSettings> load({required ApiKeyStore keyStore}) async {
    final values = await Future.wait<String?>(<Future<String?>>[
      _storage.read(key: _providerKey),
      _storage.read(key: _baseUrlKey),
      _storage.read(key: _modelKey),
      _storage.read(key: _persistenceKey),
      _storage.read(key: _useInChatKey),
    ]);

    final persistence = values[3] == ApiKeyPersistence.session.name
        ? ApiKeyPersistence.session
        : ApiKeyPersistence.device;
    final storedBaseUrl = values[1] ?? '';
    final provider = values[0] == null
        ? (storedBaseUrl.isEmpty
              ? openAiPersonalApiProvider
              : inferPersonalApiProvider(storedBaseUrl))
        : personalApiProviderById(values[0]!);
    final apiKey = await keyStore.read(
      providerId: personalApiProviderId,
      persistence: persistence,
    );
    final hasApiKey = apiKey != null && apiKey.trim().isNotEmpty;

    return PersonalApiSettings(
      providerId: provider.id,
      baseUrl: provider.custom ? storedBaseUrl : '',
      model: values[2] ?? '',
      apiKeyPersistence: persistence,
      useInChat: values[4] == 'true' && hasApiKey,
      hasApiKey: hasApiKey,
    );
  }

  Future<void> save(PersonalApiSettings settings) async {
    await Future.wait<void>(<Future<void>>[
      _storage.write(key: _providerKey, value: settings.providerId),
      _storage.write(key: _baseUrlKey, value: settings.baseUrl.trim()),
      _storage.write(key: _modelKey, value: settings.model.trim()),
      _storage.write(
        key: _persistenceKey,
        value: settings.apiKeyPersistence.name,
      ),
      _storage.write(key: _useInChatKey, value: settings.useInChat.toString()),
    ]);
  }
}

LlmBackend createPersonalApiRemoteBackend({
  required PersonalApiSettings settings,
  required ApiKeyStore keyStore,
}) {
  switch (settings.provider.protocol) {
    case PersonalApiProtocol.gemini:
      return GeminiBackend(
        model: settings.model,
        keyStore: keyStore,
        apiKeyPersistence: settings.apiKeyPersistence,
      );
    case PersonalApiProtocol.openAiResponses:
      return OpenAiResponsesBackend(
        provider: settings.toProviderConfig(),
        keyStore: keyStore,
      );
    case PersonalApiProtocol.openAiCompatible:
      return OpenAiCompatibleBackend(
        provider: settings.toProviderConfig(),
        keyStore: keyStore,
      );
  }
}

bool isAllowedPersonalApiBaseUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return false;
  }
  if (uri.scheme == 'https') {
    return true;
  }
  return uri.scheme == 'http' && _isPrivateOrLoopbackHost(uri.host);
}

bool _isPrivateOrLoopbackHost(String host) {
  final normalized = host.toLowerCase();
  if (normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1') {
    return true;
  }

  final parts = normalized.split('.');
  if (parts.length != 4) {
    return false;
  }
  final octets = parts.map(int.tryParse).toList(growable: false);
  if (octets.any((value) => value == null || value < 0 || value > 255)) {
    return false;
  }

  final first = octets[0]!;
  final second = octets[1]!;
  return first == 10 ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 168);
}

Future<void> testPersonalApiConnection({
  required PersonalApiSettings settings,
  required ApiKeyStore keyStore,
}) async {
  if (!settings.isConfigured) {
    throw StateError('Configure le fournisseur, le modèle et la clé API.');
  }

  final backend = createPersonalApiRemoteBackend(
    settings: settings,
    keyStore: keyStore,
  );

  try {
    var receivedContent = false;
    await for (final chunk in backend.generate(
      messages: const <ChatMessage>[
        ChatMessage.user('Réponds uniquement par OK.'),
      ],
      settings: const GenerationSettings(temperature: 0, topP: 1, maxTokens: 8),
    )) {
      if (chunk.trim().isNotEmpty) {
        receivedContent = true;
        await backend.stop();
        break;
      }
    }

    if (!receivedContent) {
      throw StateError('Le fournisseur a répondu sans contenu texte.');
    }
  } finally {
    await backend.dispose();
  }
}

String describePersonalApiError(Object error) {
  if (error is PersonalApiHttpException) {
    return _describeHttpError(error.statusCode, error.body);
  }
  if (error is StateError) {
    return error.message.toString();
  }
  if (error is FormatException) {
    return error.message;
  }
  return error.toString();
}

String _describeHttpError(int statusCode, String body) {
  String? code;
  String? message;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      final rawError = decoded['error'];
      if (rawError is Map<String, dynamic>) {
        code = rawError['code']?.toString();
        message = rawError['message']?.toString();
      } else if (rawError is String) {
        message = rawError;
      }
    }
  } catch (_) {
    // Le corps brut reste disponible comme dernier recours ci-dessous.
  }

  switch (code) {
    case 'credit_balance_exhausted':
    case 'insufficient_quota':
      return 'Aucun crédit API disponible pour le compte lié à cette clé.';
    case 'invalid_api_key':
      return 'La clé API est invalide ou a été révoquée.';
  }

  if (statusCode == 401 || statusCode == 403) {
    return 'Clé API refusée par le fournisseur.';
  }
  if (statusCode == 429) {
    return message?.isNotEmpty == true
        ? 'Limite ou quota du fournisseur atteint : $message'
        : 'Limite ou quota du fournisseur atteint.';
  }
  if (message?.isNotEmpty == true) {
    return 'HTTP $statusCode : $message';
  }
  if (body.trim().isNotEmpty && body.length <= 240) {
    return 'HTTP $statusCode : ${body.trim()}';
  }
  return 'Le fournisseur a répondu avec l’erreur HTTP $statusCode.';
}
