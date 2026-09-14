// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:foxllm/core/storage/api_key_store.dart';
import 'package:foxllm/llm/personal_api/personal_api_provider.dart';
import 'package:foxllm/llm/personal_api/personal_api_settings.dart';
import 'package:foxllm/llm/personal_api/provider_config.dart';

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

    // Une clé appartient à un destinataire, pas seulement à un fournisseur :
    // « Personnalisé » garde son identifiant quand la base URL change d'hôte
    // ou de chemin. Réutiliser la clé sur ce seul critère l'aurait envoyée
    // ailleurs.
    final nextDestination = personalApiDestination(
      provider.resolveBaseUrl(baseUrl.trim()),
    );
    final destinationChanged =
        current.providerId != provider.id ||
        current.apiKeyDestination != nextDestination;

    var hasApiKey = current.hasApiKey && !destinationChanged;
    if (destinationChanged && trimmedKey.isEmpty) {
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
      apiKeyDestination: hasApiKey ? nextDestination : '',
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
    // Injecté par les tests, qui vérifient à quel hôte la clé est envoyée.
    http.Client? client,
  }) async {
    final provider = personalApiProviderById(providerId);
    final current = state.value ?? const PersonalApiSettings();
    var key = apiKey?.trim() ?? '';

    // Même règle qu'à l'enregistrement, et elle compte davantage ici : la
    // récupération des modèles part avant tout enregistrement, donc avec la
    // base URL en cours de saisie.
    final requestedDestination = personalApiDestination(
      provider.resolveBaseUrl(baseUrl.trim()),
    );
    if (key.isEmpty &&
        current.providerId == provider.id &&
        current.hasApiKey &&
        current.apiKeyDestination.isNotEmpty &&
        current.apiKeyDestination == requestedDestination) {
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
      client: client,
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
    final next = current.copyWith(
      hasApiKey: false,
      useInChat: false,
      apiKeyDestination: '',
    );
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
