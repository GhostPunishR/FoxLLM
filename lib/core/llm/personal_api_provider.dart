import 'dart:convert';

import 'package:http/http.dart' as http;

enum PersonalApiProtocol { openAiCompatible, gemini }

class PersonalApiProvider {
  const PersonalApiProvider({
    required this.id,
    required this.displayName,
    required this.protocol,
    required this.baseUrl,
    this.modelsPath = 'models',
    this.custom = false,
  });

  final String id;
  final String displayName;
  final PersonalApiProtocol protocol;
  final String baseUrl;
  final String modelsPath;
  final bool custom;

  String resolveBaseUrl(String customBaseUrl) {
    if (custom) {
      return customBaseUrl.trim();
    }
    return baseUrl;
  }
}

const openAiPersonalApiProvider = PersonalApiProvider(
  id: 'openai',
  displayName: 'OpenAI',
  protocol: PersonalApiProtocol.openAiCompatible,
  baseUrl: 'https://api.openai.com/v1',
);

const groqPersonalApiProvider = PersonalApiProvider(
  id: 'groq',
  displayName: 'Groq',
  protocol: PersonalApiProtocol.openAiCompatible,
  baseUrl: 'https://api.groq.com/openai/v1',
);

const mistralPersonalApiProvider = PersonalApiProvider(
  id: 'mistral',
  displayName: 'Mistral AI',
  protocol: PersonalApiProtocol.openAiCompatible,
  baseUrl: 'https://api.mistral.ai/v1',
);

const openRouterPersonalApiProvider = PersonalApiProvider(
  id: 'openrouter',
  displayName: 'OpenRouter',
  protocol: PersonalApiProtocol.openAiCompatible,
  baseUrl: 'https://openrouter.ai/api/v1',
);

const xAiPersonalApiProvider = PersonalApiProvider(
  id: 'xai',
  displayName: 'xAI',
  protocol: PersonalApiProtocol.openAiCompatible,
  baseUrl: 'https://api.x.ai/v1',
  modelsPath: 'language-models',
);

const geminiPersonalApiProvider = PersonalApiProvider(
  id: 'gemini',
  displayName: 'Google Gemini',
  protocol: PersonalApiProtocol.gemini,
  baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
);

const customPersonalApiProvider = PersonalApiProvider(
  id: 'custom',
  displayName: 'Personnalisé (OpenAI-compatible)',
  protocol: PersonalApiProtocol.openAiCompatible,
  baseUrl: '',
  custom: true,
);

const personalApiProviders = <PersonalApiProvider>[
  openAiPersonalApiProvider,
  geminiPersonalApiProvider,
  groqPersonalApiProvider,
  mistralPersonalApiProvider,
  openRouterPersonalApiProvider,
  xAiPersonalApiProvider,
  customPersonalApiProvider,
];

PersonalApiProvider personalApiProviderById(String id) {
  return personalApiProviders.firstWhere(
    (provider) => provider.id == id,
    orElse: () => customPersonalApiProvider,
  );
}

PersonalApiProvider inferPersonalApiProvider(String baseUrl) {
  final normalized = baseUrl.trim().toLowerCase();
  for (final provider in personalApiProviders) {
    if (provider.custom || provider.baseUrl.isEmpty) {
      continue;
    }
    if (normalized == provider.baseUrl.toLowerCase()) {
      return provider;
    }
  }
  return customPersonalApiProvider;
}

Future<List<String>> fetchPersonalApiModels({
  required PersonalApiProvider provider,
  required String apiKey,
  String customBaseUrl = '',
  http.Client? client,
}) async {
  final key = apiKey.trim();
  if (key.isEmpty) {
    throw StateError('Entre une clé API avant de récupérer les modèles.');
  }

  final baseUrl = _normalizeBaseUrl(provider.resolveBaseUrl(customBaseUrl));
  if (baseUrl.isEmpty) {
    throw StateError('Configure la base URL du fournisseur personnalisé.');
  }

  final ownedClient = client == null;
  final httpClient = client ?? http.Client();
  try {
    var uri = Uri.parse('$baseUrl/${provider.modelsPath}');
    final headers = <String, String>{'Accept': 'application/json'};

    if (provider.protocol == PersonalApiProtocol.gemini) {
      headers['x-goog-api-key'] = key;
      uri = uri.replace(queryParameters: <String, String>{'pageSize': '1000'});
    } else {
      headers['Authorization'] = 'Bearer $key';
      if (provider.id == openRouterPersonalApiProvider.id) {
        uri = uri.replace(
          queryParameters: <String, String>{'output_modalities': 'text'},
        );
      }
    }

    final response = await httpClient.get(uri, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PersonalApiHttpException(
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Réponse de modèles invalide.');
    }

    final rawModels = provider.id == xAiPersonalApiProvider.id ||
            provider.protocol == PersonalApiProtocol.gemini
        ? decoded['models']
        : decoded['data'];
    if (rawModels is! List) {
      throw const FormatException('Liste de modèles absente de la réponse.');
    }

    final models = <String>{};
    for (final rawModel in rawModels) {
      if (rawModel is! Map<String, dynamic>) {
        continue;
      }

      if (provider.id == mistralPersonalApiProvider.id) {
        final capabilities = rawModel['capabilities'];
        if (capabilities is Map<String, dynamic> &&
            capabilities['completion_chat'] == false) {
          continue;
        }
      }

      if (provider.protocol == PersonalApiProtocol.gemini &&
          !_geminiSupportsGenerateContent(rawModel)) {
        continue;
      }

      final rawId = provider.protocol == PersonalApiProtocol.gemini
          ? rawModel['name']
          : rawModel['id'];
      if (rawId is! String || rawId.trim().isEmpty) {
        continue;
      }

      final id = rawId.startsWith('models/')
          ? rawId.substring('models/'.length)
          : rawId;
      if (_isClearlyNonChatModel(provider, id)) {
        continue;
      }
      models.add(id);
    }

    final result = models.toList()..sort();
    if (result.isEmpty) {
      throw StateError('Aucun modèle de chat disponible avec cette clé API.');
    }
    return result;
  } finally {
    if (ownedClient) {
      httpClient.close();
    }
  }
}

bool _geminiSupportsGenerateContent(Map<String, dynamic> model) {
  final methods = model['supportedGenerationMethods'];
  if (methods is List) {
    return methods.contains('generateContent');
  }
  final actions = model['supportedActions'];
  if (actions is List) {
    return actions.contains('generateContent');
  }
  return true;
}

bool _isClearlyNonChatModel(PersonalApiProvider provider, String modelId) {
  if (provider.id == openRouterPersonalApiProvider.id ||
      provider.id == mistralPersonalApiProvider.id ||
      provider.id == xAiPersonalApiProvider.id ||
      provider.protocol == PersonalApiProtocol.gemini ||
      provider.custom) {
    return false;
  }

  final id = modelId.toLowerCase();
  const excluded = <String>[
    'embedding',
    'whisper',
    'transcribe',
    'tts',
    'image',
    'moderation',
    'realtime',
    'audio',
    'guard',
  ];
  return excluded.any(id.contains);
}

String _normalizeBaseUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.endsWith('/')) {
    return trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

class PersonalApiHttpException implements Exception {
  const PersonalApiHttpException({required this.statusCode, required this.body});

  final int statusCode;
  final String body;

  @override
  String toString() => 'HTTP $statusCode: $body';
}
