import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../security/api_key_store.dart';
import 'personal_api_provider.dart';
import 'personal_api_settings.dart';
import 'provider_config.dart';

final apiKeyStoreProvider = Provider<ApiKeyStore>((ref) => ApiKeyStore());

final personalApiSettingsStoreProvider = Provider<PersonalApiSettingsStore>(
  (ref) => PersonalApiSettingsStore(),
);

final personalApiSettingsProvider =
    AsyncNotifierProvider<PersonalApiSettingsController, PersonalApiSettings>(
      PersonalApiSettingsController.new,
    );

class PersonalApiSettingsController extends AsyncNotifier<PersonalApiSettings> {
  @override
  Future<PersonalApiSettings> build() async {
    return ref
        .read(personalApiSettingsStoreProvider)
        .load(keyStore: ref.read(apiKeyStoreProvider));
  }

  Future<PersonalApiSettings> save({
    required String providerId,
    required String baseUrl,
    required String model,
    required ApiKeyPersistence persistence,
    required bool useInChat,
    String? apiKey,
  }) async {
    final current = state.value ?? const PersonalApiSettings();
    final provider = personalApiProviderById(providerId);
    final keyStore = ref.read(apiKeyStoreProvider);
    final trimmedKey = apiKey?.trim() ?? '';
    final providerChanged = current.providerId != provider.id;

    var hasApiKey = current.hasApiKey && !providerChanged;
    if (providerChanged && trimmedKey.isEmpty) {
      await keyStore.delete(personalApiProviderId);
      hasApiKey = false;
    }

    if (trimmedKey.isNotEmpty) {
      await keyStore.save(
        providerId: personalApiProviderId,
        apiKey: trimmedKey,
        persistence: persistence,
      );
      hasApiKey = true;
    } else if (hasApiKey && current.apiKeyPersistence != persistence) {
      final existingKey = await keyStore.read(
        providerId: personalApiProviderId,
        persistence: current.apiKeyPersistence,
      );
      if (existingKey != null && existingKey.trim().isNotEmpty) {
        await keyStore.save(
          providerId: personalApiProviderId,
          apiKey: existingKey,
          persistence: persistence,
        );
      } else {
        hasApiKey = false;
      }
    }

    final next = PersonalApiSettings(
      providerId: provider.id,
      baseUrl: provider.custom ? baseUrl.trim() : '',
      model: model.trim(),
      apiKeyPersistence: persistence,
      useInChat: useInChat && hasApiKey && model.trim().isNotEmpty,
      hasApiKey: hasApiKey,
    );

    if (provider.custom && !isAllowedPersonalApiBaseUrl(next.baseUrl)) {
      throw ArgumentError(
        'Utilise HTTPS, ou HTTP uniquement sur localhost/réseau privé.',
      );
    }

    await ref.read(personalApiSettingsStoreProvider).save(next);
    state = AsyncData<PersonalApiSettings>(next);
    return next;
  }

  Future<List<String>> fetchModels({
    required String providerId,
    required String baseUrl,
    String? apiKey,
  }) async {
    final provider = personalApiProviderById(providerId);
    final current = state.value ?? const PersonalApiSettings();
    var key = apiKey?.trim() ?? '';

    if (key.isEmpty && current.providerId == provider.id && current.hasApiKey) {
      key =
          await ref
              .read(apiKeyStoreProvider)
              .read(
                providerId: personalApiProviderId,
                persistence: current.apiKeyPersistence,
              ) ??
          '';
    }

    if (provider.custom && !isAllowedPersonalApiBaseUrl(baseUrl)) {
      throw ArgumentError(
        'Utilise HTTPS, ou HTTP uniquement sur localhost/réseau privé.',
      );
    }

    return fetchPersonalApiModels(
      provider: provider,
      apiKey: key,
      customBaseUrl: baseUrl,
    );
  }

  Future<PersonalApiSettings> setUseInChat(bool value) async {
    final current = state.requireValue;
    final next = current.copyWith(useInChat: value && current.isConfigured);
    await ref.read(personalApiSettingsStoreProvider).save(next);
    state = AsyncData<PersonalApiSettings>(next);
    return next;
  }

  Future<PersonalApiSettings> deleteApiKey() async {
    final current = state.requireValue;
    await ref.read(apiKeyStoreProvider).delete(personalApiProviderId);
    final next = current.copyWith(hasApiKey: false, useInChat: false);
    await ref.read(personalApiSettingsStoreProvider).save(next);
    state = AsyncData<PersonalApiSettings>(next);
    return next;
  }

  Future<void> testConnection() async {
    final current = state.requireValue;
    await testPersonalApiConnection(
      settings: current,
      keyStore: ref.read(apiKeyStoreProvider),
    );
  }
}
