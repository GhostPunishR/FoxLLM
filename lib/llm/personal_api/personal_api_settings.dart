// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:foxllm/core/storage/api_key_store.dart';
import 'package:foxllm/l10n/app_localizations.dart';
import 'package:foxllm/llm/backend/anthropic_backend.dart';
import 'package:foxllm/llm/backend/backend_failure.dart';
import 'package:foxllm/llm/backend/gemini_backend.dart';
import 'package:foxllm/llm/backend/llm_backend.dart';
import 'package:foxllm/llm/backend/llm_http.dart'
    show PersonalApiTimeoutException, PersonalApiTimeoutKind;
import 'package:foxllm/llm/backend/local_engine_error.dart';
import 'package:foxllm/llm/backend/openai_compatible_backend.dart';
import 'package:foxllm/llm/backend/openai_responses_backend.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
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
    this.apiKeyDestination = '',
  });

  final String providerId;
  final String baseUrl;
  final String model;
  final ApiKeyPersistence apiKeyPersistence;
  final bool useInChat;
  final bool hasApiKey;

  /// Destinataire auquel la clé enregistrée a été confiée.
  ///
  /// Le seul identifiant du fournisseur ne suffit pas : « Personnalisé » garde
  /// le même identifiant quand la base URL change d'hôte ou de chemin. Sans ce
  /// destinataire, la clé du serveur précédent partirait vers le nouveau.
  final String apiKeyDestination;

  PersonalApiProvider get provider => personalApiProviderById(providerId);

  String get effectiveBaseUrl => provider.resolveBaseUrl(baseUrl);

  /// Destinataire visé par les réglages courants.
  String get destination => personalApiDestination(effectiveBaseUrl);

  /// Vrai quand la clé enregistrée appartient bien au destinataire
  /// actuellement configuré, donc quand elle peut lui être envoyée.
  bool get hasApiKeyForCurrentDestination =>
      hasApiKey &&
      apiKeyDestination.isNotEmpty &&
      apiKeyDestination == destination;

  bool get isConfigured =>
      effectiveBaseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty &&
      hasApiKeyForCurrentDestination;

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
    String? apiKeyDestination,
  }) {
    return PersonalApiSettings(
      providerId: providerId ?? this.providerId,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      apiKeyPersistence: apiKeyPersistence ?? this.apiKeyPersistence,
      useInChat: useInChat ?? this.useInChat,
      hasApiKey: hasApiKey ?? this.hasApiKey,
      apiKeyDestination: apiKeyDestination ?? this.apiKeyDestination,
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
  static const _apiKeyDestinationKey =
      'foxllm.personal_api.api_key_destination';

  final FlutterSecureStorage _storage;

  Future<PersonalApiSettings> load({required ApiKeyStore keyStore}) async {
    final values = await Future.wait<String?>(<Future<String?>>[
      _storage.read(key: _providerKey),
      _storage.read(key: _baseUrlKey),
      _storage.read(key: _modelKey),
      _storage.read(key: _persistenceKey),
      _storage.read(key: _useInChatKey),
      _storage.read(key: _apiKeyDestinationKey),
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
    final baseUrl = provider.custom ? storedBaseUrl : '';

    // Réglages écrits avant que le destinataire soit conservé : la clé était
    // jusqu'ici envoyée à la base URL enregistrée, c'est donc bien à ce
    // destinataire qu'elle appartient. Le déduire évite de faire ressaisir sa
    // clé à qui n'a rien changé, sans jamais élargir sa portée.
    final storedDestination = values[5];
    final apiKeyDestination = hasApiKey
        ? (storedDestination == null || storedDestination.isEmpty
              ? personalApiDestination(provider.resolveBaseUrl(baseUrl))
              : storedDestination)
        : '';

    return PersonalApiSettings(
      providerId: provider.id,
      baseUrl: baseUrl,
      model: values[2] ?? '',
      apiKeyPersistence: persistence,
      useInChat: values[4] == 'true' && hasApiKey,
      hasApiKey: hasApiKey,
      apiKeyDestination: apiKeyDestination,
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
      _storage.write(
        key: _apiKeyDestinationKey,
        value: settings.apiKeyDestination,
      ),
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
    case PersonalApiProtocol.anthropic:
      return AnthropicBackend(
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
  AppLocalizations? l10n,
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
      messages: <ChatMessage>[
        // L'invite part au modèle : elle suit la langue de l'interface, sinon
        // un utilisateur anglophone verrait son fournisseur répondre à une
        // consigne française. Nulle quand l'appelant n'a pas de contexte, ce
        // qui n'arrive qu'aux bancs.
        ChatMessage.user(l10n?.apiTestPrompt ?? 'Réponds uniquement par OK.'),
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

String describePersonalApiError(Object error, AppLocalizations l10n) {
  if (error is PersonalApiHttpException) {
    return _describeHttpError(error.statusCode, error.body, l10n);
  }
  if (error is PersonalApiTimeoutException) {
    // Les exceptions construites ailleurs n'ont pas ces champs : leur message
    // français reste alors le seul texte disponible.
    final kind = error.kind;
    final provider = error.provider;
    final amount = error.amount;
    if (kind != null && provider != null && amount != null) {
      return switch (kind) {
        PersonalApiTimeoutKind.noResponse => l10n.backendNoResponse(
          provider,
          amount,
        ),
        PersonalApiTimeoutKind.streamStalled => l10n.backendStreamStalled(
          provider,
          amount,
        ),
      };
    }
    return error.message;
  }
  if (error is StateError) {
    // Le pont natif lève un `StateError` portant le message anglais du C++.
    // Sans cette reconnaissance, « Prompt exceeds the model context window. »
    // s'affichait tel quel dans le bandeau du chat, et c'est pourtant le refus
    // le plus fréquent avec un modèle local.
    final message = error.message.toString();
    final engine = LocalEngineFailure.match(message);
    if (engine != null) {
      return engine.describe(l10n);
    }
    // Même principe côté fournisseurs : ces refus naissent hors de tout
    // widget, donc sans traductions à portée.
    final backend = BackendFailure.match(message);
    if (backend != null) {
      return backend.describe(l10n);
    }
    final missingKey = missingApiKeyProvider(message);
    if (missingKey != null) {
      return l10n.backendMissingApiKey(missingKey);
    }
    return message;
  }
  if (error is FormatException) {
    return BackendFailure.match(error.message)?.describe(l10n) ?? error.message;
  }
  return error.toString();
}

String _describeHttpError(int statusCode, String body, AppLocalizations l10n) {
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
      return l10n.httpNoCredit;
    case 'invalid_api_key':
      return l10n.httpInvalidKey;
  }

  if (statusCode == 401 || statusCode == 403) {
    return l10n.httpKeyRefused;
  }
  if (statusCode == 429) {
    return message?.isNotEmpty == true
        ? l10n.httpRateLimitedWith(message!)
        : l10n.httpRateLimited;
  }
  if (message?.isNotEmpty == true) {
    return l10n.httpStatusWith('$statusCode', message!);
  }
  if (body.trim().isNotEmpty && body.length <= 240) {
    return l10n.httpStatusWith('$statusCode', body.trim());
  }
  return l10n.httpStatusOnly('$statusCode');
}
