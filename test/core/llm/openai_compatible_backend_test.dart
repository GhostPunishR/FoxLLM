// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:foxgpt/core/llm/chat_message.dart';
import 'package:foxgpt/core/llm/openai_compatible_backend.dart';
import 'package:foxgpt/core/llm/provider_config.dart';
import 'package:foxgpt/core/security/api_key_store.dart';
import 'package:http/http.dart' as http;

void main() {
  const provider = ProviderConfig(
    id: 'test',
    displayName: 'Test Provider',
    baseUrl: 'https://example.com/v1',
    model: 'test-model',
    apiKeyPersistence: ApiKeyPersistence.session,
  );

  const messages = <ChatMessage>[ChatMessage.user('Bonjour')];

  group('OpenAiCompatibleBackend cancellation', () {
    test(
      'stop prevents a request while the API key is still loading',
      () async {
        final keyReadStarted = Completer<void>();
        final keyRead = Completer<String?>();
        final keyStore = _FakeApiKeyStore(() {
          if (!keyReadStarted.isCompleted) {
            keyReadStarted.complete();
          }
          return keyRead.future;
        });

        var clientsCreated = 0;
        final backend = OpenAiCompatibleBackend(
          provider: provider,
          keyStore: keyStore,
          clientFactory: () {
            clientsCreated += 1;
            return _HoldingClient();
          },
        );

        final generationDone = backend
            .generate(messages: messages)
            .drain<void>();

        await keyReadStarted.future;
        await backend.stop();
        keyRead.complete('secret-key');
        await generationDone;

        expect(clientsCreated, 0);
        await backend.dispose();
      },
    );

    test('stop closes every concurrently active HTTP client', () async {
      final keyStore = _FakeApiKeyStore(() async => 'secret-key');
      final clients = <_HoldingClient>[];
      final twoClientsCreated = Completer<void>();

      final backend = OpenAiCompatibleBackend(
        provider: provider,
        keyStore: keyStore,
        clientFactory: () {
          final client = _HoldingClient();
          clients.add(client);
          if (clients.length == 2 && !twoClientsCreated.isCompleted) {
            twoClientsCreated.complete();
          }
          return client;
        },
      );

      final first = backend.generate(messages: messages).drain<void>();
      final second = backend.generate(messages: messages).drain<void>();

      await twoClientsCreated.future;
      await Future.wait(clients.map((client) => client.sendStarted.future));
      await backend.stop();
      await Future.wait<void>(<Future<void>>[first, second]);

      expect(clients, hasLength(2));
      expect(clients.every((client) => client.closed), isTrue);
      await backend.dispose();
    });

    test('dispose rejects future generations', () async {
      final backend = OpenAiCompatibleBackend(
        provider: provider,
        keyStore: _FakeApiKeyStore(() async => 'secret-key'),
      );

      await backend.dispose();

      await expectLater(
        backend.generate(messages: messages).drain<void>(),
        throwsStateError,
      );
    });
  });
}

class _FakeApiKeyStore extends ApiKeyStore {
  _FakeApiKeyStore(this._read);

  final Future<String?> Function() _read;

  @override
  Future<String?> read({
    required String providerId,
    required ApiKeyPersistence persistence,
  }) {
    return _read();
  }
}

class _HoldingClient extends http.BaseClient {
  final StreamController<List<int>> _controller = StreamController<List<int>>();
  final Completer<void> sendStarted = Completer<void>();

  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!sendStarted.isCompleted) {
      sendStarted.complete();
    }
    return http.StreamedResponse(_controller.stream, 200);
  }

  @override
  void close() {
    if (closed) {
      return;
    }

    closed = true;
    unawaited(_controller.close());
    super.close();
  }
}
