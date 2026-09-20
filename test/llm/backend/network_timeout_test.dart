// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/storage/api_key_store.dart';
import 'package:foxllm/llm/backend/llm_http.dart';
import 'package:foxllm/llm/backend/openai_compatible_backend.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/personal_api/personal_api_provider.dart';
import 'package:foxllm/llm/personal_api/provider_config.dart';
import 'package:http/http.dart' as http;

/// Un réseau mobile ne prévient pas quand il abandonne une connexion, et un
/// fournisseur d'en face ne ferme pas toujours ce qu'il a ouvert. Sans délai,
/// l'application attendait indéfiniment : le rond tournait, et rien ne disait
/// que plus rien ne viendrait.
const _provider = ProviderConfig(
  id: 'openai',
  displayName: 'OpenAI',
  baseUrl: 'https://api.openai.com/v1',
  model: 'gpt-5',
);

const _question = ChatMessage.user('Bonjour');

void main() {
  group('génération', () {
    test('un fournisseur qui ne répond jamais finit par lever', () async {
      final backend = _backend(_SilentClient.new);

      await expectLater(
        backend.generate(messages: <ChatMessage>[_question]).toList(),
        throwsA(
          isA<PersonalApiTimeoutException>().having(
            (e) => e.message,
            'message',
            contains('OpenAI'),
          ),
        ),
      );
    });

    test('un flux ouvert puis muet finit par lever', () async {
      // Le cas vicieux : la connexion est acceptée, quelques mots arrivent,
      // puis plus rien. Sans chien de garde, le flux reste ouvert pour
      // toujours et la réponse partielle n'est jamais rendue ni signalée.
      final client = _StallingClient();
      final backend = _backend(() => client);

      final received = <String>[];
      await expectLater(
        backend
            .generate(messages: <ChatMessage>[_question])
            .forEach(received.add),
        throwsA(isA<PersonalApiTimeoutException>()),
      );
      // Le texte déjà reçu n'est pas perdu au passage.
      expect(received.join(), 'Début');
    });

    test('des battements de cœur ne tiennent pas le flux en vie', () async {
      // Un `: ping` n'est pas un progrès. OpenRouter en envoie, les proxys en
      // intercalent : si chacun relançait le chien de garde, un fournisseur
      // bloqué derrière un proxy bavard ferait tourner le rond pour toujours,
      // et le délai ne protégerait plus de rien.
      final client = _HeartbeatClient();
      final backend = _backend(() => client);

      await expectLater(
        backend.generate(messages: <ChatMessage>[_question]).toList(),
        throwsA(isA<PersonalApiTimeoutException>()),
      );
    });

    test('un corps d’erreur qui ne vient jamais n’attend pas', () async {
      // Le délai de réponse s'arrête aux en-têtes : un fournisseur qui
      // annonce 500 puis se tait en écrivant le détail échappait ensuite à
      // tout délai. L'échec est déjà connu, il doit être signalé.
      final client = _StallingErrorClient();
      final backend = _backend(() => client);

      await expectLater(
        backend.generate(messages: <ChatMessage>[_question]).toList(),
        throwsA(
          isA<PersonalApiHttpException>().having(
            (e) => e.statusCode,
            'statusCode',
            500,
          ),
        ),
      );
    });

    test('un flux qui avance n’est pas coupé par le délai', () async {
      // Le délai compte le silence, pas la durée : une réponse lente mais qui
      // progresse doit aller au bout, sinon un modèle qui réfléchit serait
      // interrompu en plein raisonnement.
      final client = _SlowClient(
        gap: const Duration(milliseconds: 30),
        pieces: 6,
      );
      final backend = _backend(() => client);

      expect(
        await backend.generate(messages: <ChatMessage>[_question]).join(),
        'atatatatatat'.substring(0, 12),
      );
    });
  });

  group('découverte des modèles', () {
    test('un fournisseur muet ne laisse pas l’écran des réglages en rond', () {
      // Le même délai vaut ici : sans lui, tester une clé sur un fournisseur
      // injoignable bloquait l'écran jusqu'à ce qu'on le quitte.
      expect(modelsTimeout.inSeconds, greaterThan(0));
      expect(modelsTimeout.inSeconds, lessThanOrEqualTo(60));
    });
  });

  group('valeurs par défaut', () {
    test('les délais sont généreux, mais finis', () {
      final backend = OpenAiCompatibleBackend(
        provider: _provider,
        keyStore: _FakeApiKeyStore(),
      );
      addTearDown(backend.dispose);

      // Assez larges pour ne pas couper un modèle qui réfléchit.
      expect(backend.responseTimeout.inSeconds, greaterThanOrEqualTo(60));
      expect(backend.idleTimeout.inMinutes, greaterThanOrEqualTo(2));
      // Mais bornés : c'est tout l'objet du correctif.
      expect(backend.responseTimeout.inMinutes, lessThanOrEqualTo(5));
      expect(backend.idleTimeout.inMinutes, lessThanOrEqualTo(10));
      // Le corps d'une réponse en échec n'a pas à se faire attendre autant :
      // le code HTTP a déjà tout dit, ce corps n'ajoute que le détail.
      expect(backend.errorBodyTimeout.inSeconds, greaterThan(0));
      expect(backend.errorBodyTimeout, lessThan(backend.responseTimeout));
    });
  });
}

_ImpatientBackend _backend(HttpClientFactory clientFactory) {
  final backend = _ImpatientBackend(
    provider: _provider,
    keyStore: _FakeApiKeyStore(),
    clientFactory: clientFactory,
  );
  addTearDown(backend.dispose);
  return backend;
}

/// Mêmes délais, en millisecondes : un test n'a pas à patienter une minute et
/// demie pour vérifier une seconde.
class _ImpatientBackend extends OpenAiCompatibleBackend {
  _ImpatientBackend({
    required super.provider,
    required super.keyStore,
    super.clientFactory,
  });

  @override
  Duration get responseTimeout => const Duration(milliseconds: 80);

  @override
  Duration get idleTimeout => const Duration(milliseconds: 80);

  @override
  Duration get errorBodyTimeout => const Duration(milliseconds: 80);
}

class _FakeApiKeyStore extends ApiKeyStore {
  @override
  Future<String?> read({
    required String providerId,
    required ApiKeyPersistence persistence,
  }) async => 'secret';
}

/// N'accuse jamais réception : la connexion reste en attente.
class _SilentClient extends http.BaseClient {
  final Completer<http.StreamedResponse> _never =
      Completer<http.StreamedResponse>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _never.future;

  @override
  void close() {
    if (!_never.isCompleted) {
      _never.completeError(const _ClosedByClient());
    }
  }
}

class _ClosedByClient implements Exception {
  const _ClosedByClient();
}

/// Répond, envoie un fragment, puis se tait sans fermer le flux.
class _StallingClient extends http.BaseClient {
  final StreamController<List<int>> _body = StreamController<List<int>>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _body.add(
      utf8.encode('data: {"choices":[{"delta":{"content":"Début"}}]}\n\n'),
    );
    return http.StreamedResponse(_body.stream, 200);
  }

  @override
  void close() {
    unawaited(_body.close());
  }
}

/// Répond par petits morceaux espacés, sans jamais dépasser le délai.
class _SlowClient extends http.BaseClient {
  _SlowClient({required this.gap, required this.pieces});

  final Duration gap;
  final int pieces;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = StreamController<List<int>>();
    unawaited(() async {
      for (var index = 0; index < pieces; index++) {
        await Future<void>.delayed(gap);
        if (body.isClosed) {
          return;
        }
        body.add(
          utf8.encode('data: {"choices":[{"delta":{"content":"at"}}]}\n\n'),
        );
      }
      await body.close();
    }());
    return http.StreamedResponse(body.stream, 200);
  }
}

/// Ne dit jamais rien, mais le dit souvent : que des battements de cœur.
///
/// Le cas réel d'un fournisseur dont le modèle s'est bloqué derrière un proxy
/// qui, lui, tient la connexion ouverte et le fait savoir.
class _HeartbeatClient extends http.BaseClient {
  static const _beats = 40;
  static const _gap = Duration(milliseconds: 10);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = StreamController<List<int>>();
    unawaited(() async {
      for (var beat = 0; beat < _beats; beat++) {
        await Future<void>.delayed(_gap);
        if (body.isClosed) {
          return;
        }
        body.add(utf8.encode(': ping\n\n'));
      }
      await body.close();
    }());
    return http.StreamedResponse(body.stream, 200);
  }
}

/// Annonce un échec, puis se tait au moment d'en écrire le détail.
class _StallingErrorClient extends http.BaseClient {
  final StreamController<List<int>> _body = StreamController<List<int>>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(_body.stream, 500);

  @override
  void close() {
    unawaited(_body.close());
  }
}
