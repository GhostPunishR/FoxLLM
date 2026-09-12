import 'dart:convert';

import 'package:http/http.dart' as http;

import '../security/api_key_store.dart';
import 'chat_message.dart';
import 'generation_settings.dart';
import 'llm_backend.dart';
import 'provider_config.dart';

class OpenAiCompatibleBackend implements LlmBackend {
  OpenAiCompatibleBackend({required this.provider, required this.keyStore});

  final ProviderConfig provider;
  final ApiKeyStore keyStore;

  http.Client? _activeClient;

  @override
  String get id => provider.id;

  @override
  String get displayName => provider.displayName;

  @override
  Stream<String> generate({
    required List<ChatMessage> messages,
    GenerationSettings settings = const GenerationSettings(),
  }) async* {
    final apiKey = await keyStore.read(
      providerId: provider.id,
      persistence: provider.apiKeyPersistence,
    );

    if (apiKey == null || apiKey.trim().isEmpty) {
      throw StateError(
        'Aucune clé API configurée pour ${provider.displayName}.',
      );
    }

    final client = http.Client();
    _activeClient = client;

    try {
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

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorBody = await response.stream.bytesToString();
        throw HttpException(statusCode: response.statusCode, body: errorBody);
      }

      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lines) {
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
    } finally {
      client.close();
      if (identical(_activeClient, client)) {
        _activeClient = null;
      }
    }
  }

  @override
  Future<void> stop() async {
    _activeClient?.close();
    _activeClient = null;
  }

  @override
  Future<void> dispose() => stop();
}

class HttpException implements Exception {
  const HttpException({required this.statusCode, required this.body});

  final int statusCode;
  final String body;

  @override
  String toString() => 'HTTP $statusCode: $body';
}
