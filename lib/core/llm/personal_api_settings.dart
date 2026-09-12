import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../security/api_key_store.dart';
import 'chat_message.dart';
import 'generation_settings.dart';
import 'openai_compatible_backend.dart';
import 'provider_config.dart';

const personalApiProviderId = 'personal-api';

class PersonalApiSettings {
  const PersonalApiSettings({
    this.baseUrl = '',
    this.model = '',
    this.apiKeyPersistence = ApiKeyPersistence.device,
    this.useInChat = false,
    this.hasApiKey = false,
  });

  final String baseUrl;
  final String model;
  final ApiKeyPersistence apiKeyPersistence;
  final bool useInChat;
  final bool hasApiKey;

  bool get isConfigured =>
      baseUrl.trim().isNotEmpty && model.trim().isNotEmpty && hasApiKey;

  ProviderConfig toProviderConfig() => ProviderConfig(
        id: personalApiProviderId,
        displayName: 'API personnelle',
        baseUrl: baseUrl.trim(),
        model: model.trim(),
        apiKeyPersistence: apiKeyPersistence,
      );

  PersonalApiSettings copyWith({
    String? baseUrl,
    String? model,
    ApiKeyPersistence? apiKeyPersistence,
    bool? useInChat,
    bool? hasApiKey,
  }) {
    return PersonalApiSettings(
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

  static const _baseUrlKey = 'foxgpt.personal_api.base_url';
  static const _modelKey = 'foxgpt.personal_api.model';
  static const _persistenceKey = 'foxgpt.personal_api.persistence';
  static const _useInChatKey = 'foxgpt.personal_api.use_in_chat';

  final FlutterSecureStorage _storage;

  Future<PersonalApiSettings> load({required ApiKeyStore keyStore}) async {
    final values = await Future.wait<String?>(<Future<String?>>[
      _storage.read(key: _baseUrlKey),
      _storage.read(key: _modelKey),
      _storage.read(key: _persistenceKey),
      _storage.read(key: _useInChatKey),
    ]);

    final persistence = values[2] == ApiKeyPersistence.session.name
        ? ApiKeyPersistence.session
        : ApiKeyPersistence.device;
    final apiKey = await keyStore.read(
      providerId: personalApiProviderId,
      persistence: persistence,
    );
    final hasApiKey = apiKey != null && apiKey.trim().isNotEmpty;

    return PersonalApiSettings(
      baseUrl: values[0] ?? '',
      model: values[1] ?? '',
      apiKeyPersistence: persistence,
      useInChat: values[3] == 'true' && hasApiKey,
      hasApiKey: hasApiKey,
    );
  }

  Future<void> save(PersonalApiSettings settings) async {
    await Future.wait<void>(<Future<void>>[
      _storage.write(key: _baseUrlKey, value: settings.baseUrl.trim()),
      _storage.write(key: _modelKey, value: settings.model.trim()),
      _storage.write(
        key: _persistenceKey,
        value: settings.apiKeyPersistence.name,
      ),
      _storage.write(
        key: _useInChatKey,
        value: settings.useInChat.toString(),
      ),
    ]);
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
  if (normalized == 'localhost' || normalized == '127.0.0.1' || normalized == '::1') {
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
    throw StateError('Configure la base URL, le modèle et la clé API.');
  }

  final backend = OpenAiCompatibleBackend(
    provider: settings.toProviderConfig(),
    keyStore: keyStore,
  );

  try {
    var receivedContent = false;
    await for (final chunk in backend.generate(
      messages: const <ChatMessage>[
        ChatMessage.user('Réponds uniquement par OK.'),
      ],
      settings: const GenerationSettings(
        temperature: 0,
        topP: 1,
        maxTokens: 8,
      ),
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
