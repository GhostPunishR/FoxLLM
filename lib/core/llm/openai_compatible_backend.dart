import 'dart:convert';

import 'package:http/http.dart' as http;

import '../security/api_key_store.dart';
import 'chat_message.dart';
import 'generation_settings.dart';
import 'llm_backend.dart';
import 'provider_config.dart';

typedef HttpClientFactory = http.Client Function();

class OpenAiCompatibleBackend implements LlmBackend {
  OpenAiCompatibleBackend({
    required this.provider,
    required this.keyStore,
    HttpClientFactory? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client;

  final ProviderConfig provider;
  final ApiKeyStore keyStore;
  final HttpClientFactory _clientFactory;

  final Set<_GenerationState> _activeGenerations = <_GenerationState>{};
  bool _disposed = false;

  @override
  String get id => provider.id;

  @override
  String get displayName => provider.displayName;

  @override
  Stream<String> generate({
    required List<ChatMessage> messages,
    GenerationSettings settings = const GenerationSettings(),
  }) async* {
    if (_disposed) {
      throw StateError('Le backend $displayName a déjà été libéré.');
    }

    final generation = _GenerationState();
    _activeGenerations.add(generation);

    try {
      try {
        final apiKey = await keyStore.read(
          providerId: provider.id,
          persistence: provider.apiKeyPersistence,
        );

        if (_shouldAbort(generation)) {
          return;
        }

        if (apiKey == null || apiKey.trim().isEmpty) {
          throw StateError(
            'Aucune clé API configurée pour ${provider.displayName}.',
          );
        }

        final client = _clientFactory();
        generation.attachClient(client);

        if (_shouldAbort(generation)) {
          return;
        }

        final request = http.Request('POST', provider.chatCompletionsUri)
          ..headers.addAll(<String, String>{
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          })
          ..body = jsonEncode(<String, Object>{
            'model': provider.model,
            'messages': messages.map((message) => message.toApiJson()).toList(),
            'temperature': settings.temperature,
            'top_p': settings.topP,
            'max_tokens': settings.maxTokens,
            'stream': true,
          });

        final response = await client.send(request);

        if (_shouldAbort(generation)) {
          return;
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          final errorBody = await response.stream.bytesToString();
          throw HttpException(statusCode: response.statusCode, body: errorBody);
        }

        final lines = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter());

        await for (final line in lines) {
          if (_shouldAbort(generation)) {
            return;
          }

          if (!line.startsWith('data:')) {
            continue;
          }

          final payload = line.substring(5).trim();
          if (payload.isEmpty) {
            continue;
          }
          if (payload == '[DONE]') {
            break;
          }

          final decoded = jsonDecode(payload);
          if (decoded is! Map<String, dynamic>) {
            continue;
          }

          final choices = decoded['choices'];
          if (choices is! List || choices.isEmpty) {
            continue;
          }

          final firstChoice = choices.first;
          if (firstChoice is! Map<String, dynamic>) {
            continue;
          }

          final delta = firstChoice['delta'];
          if (delta is! Map<String, dynamic>) {
            continue;
          }

          final content = delta['content'];
          if (content is String && content.isNotEmpty) {
            yield content;
          }
        }
      } catch (_) {
        if (_shouldAbort(generation)) {
          return;
        }
        rethrow;
      }
    } finally {
      generation.cancel();
      _activeGenerations.remove(generation);
    }
  }

  bool _shouldAbort(_GenerationState generation) {
    return _disposed || generation.isCancelled;
  }

  @override
  Future<void> stop() async {
    final generations = List<_GenerationState>.of(_activeGenerations);
    for (final generation in generations) {
      generation.cancel();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    await stop();
  }
}

class _GenerationState {
  http.Client? _client;
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void attachClient(http.Client client) {
    _client = client;
    if (_isCancelled) {
      client.close();
      _client = null;
    }
  }

  void cancel() {
    if (_isCancelled) {
      return;
    }

    _isCancelled = true;
    _client?.close();
    _client = null;
  }
}

class HttpException implements Exception {
  const HttpException({required this.statusCode, required this.body});

  final int statusCode;
  final String body;

  @override
  String toString() => 'HTTP $statusCode: $body';
}
