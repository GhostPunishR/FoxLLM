// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/storage/api_key_store.dart';
import 'package:foxllm/llm/personal_api/personal_api_settings.dart';
import 'package:foxllm/llm/personal_api/personal_api_settings_provider.dart';
import 'package:foxllm/llm/personal_api/provider_config.dart';
import 'package:http/http.dart' as http;

const _serverA = 'https://serveur-a.example.com/v1';
const _serverB = 'https://serveur-b.example.com/v1';
const _keyForA = 'cle-du-serveur-a';

/// Clé API en mémoire, avec les deux modes de conservation.
class _MemoryKeyStore implements ApiKeyStore {
  final Map<String, String> device = <String, String>{};
  final Map<String, String> session = <String, String>{};

  @override
  Future<void> save({
    required String providerId,
    required String apiKey,
    required ApiKeyPersistence persistence,
  }) async {
    if (persistence == ApiKeyPersistence.session) {
      session[providerId] = apiKey;
      device.remove(providerId);
      return;
    }
    device[providerId] = apiKey;
    session.remove(providerId);
  }

  @override
  Future<String?> read({
    required String providerId,
    required ApiKeyPersistence persistence,
  }) async {
    return persistence == ApiKeyPersistence.session
        ? session[providerId]
        : device[providerId];
  }

  @override
  Future<void> delete(String providerId) async {
    device.remove(providerId);
    session.remove(providerId);
  }
}

class _MemorySettingsStore implements PersonalApiSettingsStore {
  _MemorySettingsStore(this.settings);

  PersonalApiSettings settings;

  @override
  Future<PersonalApiSettings> load({required ApiKeyStore keyStore}) async =>
      settings;

  @override
  Future<void> save(PersonalApiSettings next) async => settings = next;
}

/// Note chaque requête sortante : c'est la preuve de ce qui est réellement
/// envoyé, et à qui.
class _RecordingClient extends http.BaseClient {
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final body = jsonEncode(<String, Object?>{
      'data': <Object?>[
        <String, Object?>{'id': 'modele-distant'},
      ],
    });
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );
  }
}

ProviderContainer _container({
  required _MemoryKeyStore keys,
  required _MemorySettingsStore store,
}) {
  final container = ProviderContainer(
    overrides: [
      apiKeyStoreProvider.overrideWithValue(keys),
      personalApiSettingsStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Réglages d'une installation dont la clé a été enregistrée pour le serveur A.
PersonalApiSettings _configuredForA({
  ApiKeyPersistence persistence = ApiKeyPersistence.device,
}) {
  return PersonalApiSettings(
    providerId: 'custom',
    baseUrl: _serverA,
    model: 'modele',
    apiKeyPersistence: persistence,
    useInChat: true,
    hasApiKey: true,
    apiKeyDestination: personalApiDestination(_serverA),
  );
}

void main() {
  group('personalApiDestination', () {
    test('ramène les écritures équivalentes d’une même adresse', () {
      const reference = 'https://api.example.com:443/v1';
      expect(personalApiDestination('https://api.example.com/v1'), reference);
      expect(personalApiDestination('https://api.example.com/v1/'), reference);
      expect(personalApiDestination('https://api.example.com/v1//'), reference);
      expect(personalApiDestination('https://API.Example.com/v1'), reference);
      expect(
        personalApiDestination('https://api.example.com:443/v1'),
        reference,
      );
      expect(personalApiDestination(' https://api.example.com/v1 '), reference);
    });

    test('distingue l’hôte, le port et le schéma', () {
      expect(
        personalApiDestination('https://a.example.com/v1'),
        isNot(personalApiDestination('https://b.example.com/v1')),
      );
      expect(
        personalApiDestination('http://127.0.0.1:11434/v1'),
        isNot(personalApiDestination('http://127.0.0.1:8080/v1')),
      );
      expect(
        personalApiDestination('http://192.168.1.5/v1'),
        isNot(personalApiDestination('https://192.168.1.5/v1')),
      );
    });

    test('distingue aussi le chemin', () {
      // Une passerelle peut router chaque préfixe vers un fournisseur
      // différent : même hôte ne veut pas dire mêmes identifiants.
      expect(
        personalApiDestination('https://passerelle.example.com/openai/v1'),
        isNot(
          personalApiDestination('https://passerelle.example.com/anthropic/v1'),
        ),
      );
      expect(
        personalApiDestination('https://api.example.com/v1'),
        isNot(personalApiDestination('https://api.example.com/v2')),
      );
      expect(
        personalApiDestination('https://api.example.com'),
        isNot(personalApiDestination('https://api.example.com/v1')),
      );
      // Le chemin garde sa casse : HTTP la distingue, contrairement à l'hôte.
      expect(
        personalApiDestination('https://api.example.com/V1'),
        isNot(personalApiDestination('https://api.example.com/v1')),
      );
    });

    test('rend une chaîne vide pour une valeur inexploitable', () {
      expect(personalApiDestination(''), isEmpty);
      expect(personalApiDestination('serveur-sans-schema/v1'), isEmpty);
    });
  });

  group('récupération des modèles', () {
    test('la clé du serveur A ne part jamais vers le serveur B', () async {
      final keys = _MemoryKeyStore()..device[personalApiProviderId] = _keyForA;
      final store = _MemorySettingsStore(_configuredForA());
      final container = _container(keys: keys, store: store);
      final client = _RecordingClient();

      await container.read(personalApiSettingsProvider.future);

      await expectLater(
        container
            .read(personalApiSettingsProvider.notifier)
            .fetchModels(
              providerId: 'custom',
              baseUrl: _serverB,
              client: client,
            ),
        throwsA(isA<StateError>()),
      );

      expect(client.requests, isEmpty, reason: 'aucune requête vers B');
    });

    test(
      'la clé sert encore au même serveur malgré une URL réécrite',
      () async {
        final keys = _MemoryKeyStore()
          ..device[personalApiProviderId] = _keyForA;
        final store = _MemorySettingsStore(_configuredForA());
        final container = _container(keys: keys, store: store);
        final client = _RecordingClient();

        await container.read(personalApiSettingsProvider.future);

        final models = await container
            .read(personalApiSettingsProvider.notifier)
            .fetchModels(
              // Même serveur, écrit autrement : port explicite et barre finale.
              providerId: 'custom',
              baseUrl: 'https://serveur-a.example.com:443/v1/',
              client: client,
            );

        expect(models, contains('modele-distant'));
        expect(client.requests, hasLength(1));
        expect(client.requests.single.url.host, 'serveur-a.example.com');
        expect(
          client.requests.single.headers['Authorization'],
          'Bearer $_keyForA',
        );
      },
    );

    test(
      'une clé saisie à la main part bien vers le nouveau serveur',
      () async {
        final keys = _MemoryKeyStore()
          ..device[personalApiProviderId] = _keyForA;
        final store = _MemorySettingsStore(_configuredForA());
        final container = _container(keys: keys, store: store);
        final client = _RecordingClient();

        await container.read(personalApiSettingsProvider.future);

        await container
            .read(personalApiSettingsProvider.notifier)
            .fetchModels(
              providerId: 'custom',
              baseUrl: _serverB,
              apiKey: 'cle-du-serveur-b',
              client: client,
            );

        expect(client.requests.single.url.host, 'serveur-b.example.com');
        expect(
          client.requests.single.headers['Authorization'],
          'Bearer cle-du-serveur-b',
        );
      },
    );

    test('la clé de session obéit à la même règle', () async {
      final keys = _MemoryKeyStore()..session[personalApiProviderId] = _keyForA;
      final store = _MemorySettingsStore(
        _configuredForA(persistence: ApiKeyPersistence.session),
      );
      final container = _container(keys: keys, store: store);
      final client = _RecordingClient();

      await container.read(personalApiSettingsProvider.future);

      await expectLater(
        container
            .read(personalApiSettingsProvider.notifier)
            .fetchModels(
              providerId: 'custom',
              baseUrl: _serverB,
              client: client,
            ),
        throwsA(isA<StateError>()),
      );
      expect(client.requests, isEmpty);
    });
  });

  group('chemin seul', () {
    test('changer de chemin n’envoie pas la clé au nouveau préfixe', () async {
      final keys = _MemoryKeyStore()..device[personalApiProviderId] = _keyForA;
      final store = _MemorySettingsStore(_configuredForA());
      final container = _container(keys: keys, store: store);
      final client = _RecordingClient();

      await container.read(personalApiSettingsProvider.future);

      await expectLater(
        container
            .read(personalApiSettingsProvider.notifier)
            .fetchModels(
              providerId: 'custom',
              // Même hôte, autre préfixe de routage.
              baseUrl: 'https://serveur-a.example.com/autre/v1',
              client: client,
            ),
        throwsA(isA<StateError>()),
      );

      expect(client.requests, isEmpty);
    });

    test('changer de chemin à l’enregistrement oublie la clé', () async {
      final keys = _MemoryKeyStore()..device[personalApiProviderId] = _keyForA;
      final store = _MemorySettingsStore(_configuredForA());
      final container = _container(keys: keys, store: store);

      await container.read(personalApiSettingsProvider.future);

      final next = await container
          .read(personalApiSettingsProvider.notifier)
          .save(
            providerId: 'custom',
            baseUrl: 'https://serveur-a.example.com/autre/v1',
            model: 'modele',
            persistence: ApiKeyPersistence.device,
            useInChat: true,
          );

      expect(next.hasApiKey, isFalse);
      expect(next.isConfigured, isFalse);
      expect(keys.device, isEmpty);
    });

    test('des réglages dont le chemin a changé sont incomplets', () {
      final stale = _configuredForA().copyWith(
        baseUrl: 'https://serveur-a.example.com/autre/v1',
      );

      expect(stale.hasApiKey, isTrue);
      expect(stale.hasApiKeyForCurrentDestination, isFalse);
      expect(stale.isConfigured, isFalse);
    });
  });

  group('enregistrement', () {
    test('changer de serveur oublie la clé au lieu de la reconduire', () async {
      final keys = _MemoryKeyStore()..device[personalApiProviderId] = _keyForA;
      final store = _MemorySettingsStore(_configuredForA());
      final container = _container(keys: keys, store: store);

      await container.read(personalApiSettingsProvider.future);

      final next = await container
          .read(personalApiSettingsProvider.notifier)
          .save(
            providerId: 'custom',
            baseUrl: _serverB,
            model: 'modele',
            persistence: ApiKeyPersistence.device,
            useInChat: true,
          );

      expect(next.hasApiKey, isFalse);
      expect(next.apiKeyDestination, isEmpty);
      expect(next.useInChat, isFalse, reason: 'le chat ne peut plus émettre');
      expect(next.isConfigured, isFalse);
      expect(keys.device, isEmpty, reason: 'la clé du serveur A est effacée');
    });

    test('la même adresse écrite autrement garde la clé', () async {
      final keys = _MemoryKeyStore()..device[personalApiProviderId] = _keyForA;
      final store = _MemorySettingsStore(_configuredForA());
      final container = _container(keys: keys, store: store);

      await container.read(personalApiSettingsProvider.future);

      final next = await container
          .read(personalApiSettingsProvider.notifier)
          .save(
            providerId: 'custom',
            baseUrl: 'https://serveur-a.example.com/v1/',
            model: 'modele',
            persistence: ApiKeyPersistence.device,
            useInChat: true,
          );

      expect(next.hasApiKey, isTrue);
      expect(next.isConfigured, isTrue);
      expect(keys.device[personalApiProviderId], _keyForA);
    });

    test('une nouvelle clé accompagne le nouveau serveur', () async {
      final keys = _MemoryKeyStore()..device[personalApiProviderId] = _keyForA;
      final store = _MemorySettingsStore(_configuredForA());
      final container = _container(keys: keys, store: store);

      await container.read(personalApiSettingsProvider.future);

      final next = await container
          .read(personalApiSettingsProvider.notifier)
          .save(
            providerId: 'custom',
            baseUrl: _serverB,
            model: 'modele',
            persistence: ApiKeyPersistence.device,
            useInChat: true,
            apiKey: 'cle-du-serveur-b',
          );

      expect(next.hasApiKey, isTrue);
      expect(next.apiKeyDestination, personalApiDestination(_serverB));
      expect(keys.device[personalApiProviderId], 'cle-du-serveur-b');
    });
  });

  group('migration des réglages existants', () {
    setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

    test('une clé enregistrée avant cette règle reste utilisable', () async {
      // Réglages écrits par une version qui ne conservait pas l'origine : la
      // clé servait déjà ce serveur, il ne faut pas la faire ressaisir.
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'foxllm.personal_api.provider': 'custom',
        'foxllm.personal_api.base_url': _serverA,
        'foxllm.personal_api.model': 'modele',
        'foxllm.personal_api.persistence': 'device',
        'foxllm.personal_api.use_in_chat': 'true',
      });
      final keys = _MemoryKeyStore()..device[personalApiProviderId] = _keyForA;

      final loaded = await PersonalApiSettingsStore().load(keyStore: keys);

      expect(loaded.hasApiKey, isTrue);
      expect(loaded.apiKeyDestination, personalApiDestination(_serverA));
      expect(loaded.isConfigured, isTrue);
      expect(loaded.useInChat, isTrue);
    });

    test(
      'le destinataire déduit ne couvre que l’adresse enregistrée',
      () async {
        FlutterSecureStorage.setMockInitialValues(<String, String>{
          'foxllm.personal_api.provider': 'custom',
          'foxllm.personal_api.base_url': _serverA,
          'foxllm.personal_api.model': 'modele',
          'foxllm.personal_api.persistence': 'device',
          'foxllm.personal_api.use_in_chat': 'true',
        });
        final keys = _MemoryKeyStore()
          ..device[personalApiProviderId] = _keyForA;

        final loaded = await PersonalApiSettingsStore().load(keyStore: keys);

        expect(loaded.copyWith(baseUrl: _serverB).isConfigured, isFalse);
      },
    );

    test('sans clé enregistrée, aucun destinataire n’est déduit', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'foxllm.personal_api.provider': 'custom',
        'foxllm.personal_api.base_url': _serverA,
        'foxllm.personal_api.model': 'modele',
        'foxllm.personal_api.persistence': 'device',
        'foxllm.personal_api.use_in_chat': 'true',
      });

      final loaded = await PersonalApiSettingsStore().load(
        keyStore: _MemoryKeyStore(),
      );

      expect(loaded.hasApiKey, isFalse);
      expect(loaded.apiKeyDestination, isEmpty);
    });
  });

  group('chat et test de connexion', () {
    test('des réglages dont l’adresse ne correspond plus sont incomplets', () {
      final stale = _configuredForA().copyWith(baseUrl: _serverB);

      expect(stale.hasApiKey, isTrue);
      expect(stale.hasApiKeyForCurrentDestination, isFalse);
      expect(
        stale.isConfigured,
        isFalse,
        reason: 'ni le chat ni le test de connexion ne doivent émettre',
      );
    });

    test('un destinataire absent ne vaut pas accord', () {
      const withoutOrigin = PersonalApiSettings(
        providerId: 'custom',
        baseUrl: _serverA,
        model: 'modele',
        hasApiKey: true,
      );

      expect(withoutOrigin.isConfigured, isFalse);
    });
  });
}
