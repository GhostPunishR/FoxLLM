import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../security/api_key_store.dart';
import 'chat_message.dart';
import 'generation_settings.dart';
import 'llm_backend.dart';
import 'personal_api_provider.dart';
import 'provider_config.dart';

typedef GeminiHttpClientFactory = http.Client Function();

class GeminiBackend implements LlmBackend {
  GeminiBackend({
    required this.model,
    required this.keyStore,
    required this.apiKeyPersistence,
    GeminiHttpClientFactory? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  static const providerId = 'personal-api';

  final String model;
  final ApiKeyStore keyStore;
  final ApiKeyPersistence apiKeyPersistence;
  final GeminiHttpClientFactory _clientFactory;

  final Set<_GeminiGenerationState> _activeGenerations =
      <_GeminiGenerationState>{};
  bool _disposed = false;

  @override
  String get id => 'gemini';

  @override
  String get displayName => 'Google Gemini';

  @override
  Stream<String> generate({
    required List<ChatMessage> messages,
    GenerationSettings settings = const GenerationSettings(),
  }) async* {
    if (_disposed) {
      throw StateError('Le backend $displayName a déjà été libéré.');
    }

    final generation = _GeminiGenerationState();
    _activeGenerations.add(generation);

    try {
      try {
        final apiKey = await keyStore.read(
          providerId: providerId,
          persistence: apiKeyPersistence,
        );
        if (_shouldAbort(generation)) {
          return;
        }
        if (apiKey == null || apiKey.trim().isEmpty) {
          throw StateError('Aucune clé API configurée pour Google Gemini.');
        }

        final client = _clientFactory();
        generation.attachClient(client);
        if (_shouldAbort(generation)) {
          return;
        }

        final normalizedModel = model.startsWith('models/')
            ? model.substring('models/'.length)
            : model;
        final uri = Uri.parse(
          '${geminiPersonalApiProvider.baseUrl}/models/'
          '${Uri.encodeComponent(normalizedModel)}:streamGenerateContent',
        ).replace(queryParameters: const <String, String>{'alt': 'sse'});

        final systemText = messages
            .where((message) => message.role == ChatRole.system)
            .map((message) => message.content)
            .join('\n\n');
        final contents = messages
            .where((message) => message.role != ChatRole.system)
            .map(
              (message) => <String, Object>{
                'role': message.role == ChatRole.assistant ? 'model' : 'user',
                'parts': <Map<String, String>>[
                  <String, String>{'text': message.content},
                ],
              },
            )
            .toList(growable: false);

        final body = <String, Object>{
          'contents': contents,
          'generationConfig': <String, Object>{
            'temperature': settings.temperature,
            'topP': settings.topP,
            'maxOutputTokens': settings.maxTokens,
          },
        };
        if (systemText.isNotEmpty) {
          body['systemInstruction'] = <String, Object>{
            'parts': <Map<String, String>>[
              <String, String>{'text': systemText},
            ],
          };
        }

        final request = http.Request('POST', uri)
          ..headers.addAll(<String, String>{
            'x-goog-api-key': apiKey,
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          })
          ..body = jsonEncode(body);

        final response = await client.send(request);
        if (_shouldAbort(generation)) {
          return;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final errorBody = await response.stream.bytesToString();
          throw PersonalApiHttpException(
            statusCode: response.statusCode,
            body: errorBody,
          );
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

          final decoded = jsonDecode(payload);
          if (decoded is! Map<String, dynamic>) {
            continue;
          }
          final candidates = decoded['candidates'];
          if (candidates is! List || candidates.isEmpty) {
            continue;
          }
          final candidate = candidates.first;
          if (candidate is! Map<String, dynamic>) {
            continue;
          }
          final content = candidate['content'];
          if (content is! Map<String, dynamic>) {
            continue;
          }
          final parts = content['parts'];
          if (parts is! List) {
            continue;
          }
          for (final part in parts) {
            if (part is Map<String, dynamic>) {
              final text = part['text'];
              if (text is String && text.isNotEmpty) {
                yield text;
              }
            }
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

  bool _shouldAbort(_GeminiGenerationState generation) {
    return _disposed || generation.isCancelled;
  }

  @override
  Future<void> stop() async {
    final generations = List<_GeminiGenerationState>.of(_activeGenerations);
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

class _GeminiGenerationState {
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
