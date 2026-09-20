// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:foxllm/llm/backend/llm_http.dart';
import 'package:foxllm/llm/personal_api/provider_config.dart';

export 'package:foxllm/llm/backend/llm_http.dart'
    show PersonalApiHttpException, PersonalApiTimeoutException;

/// Dialecte d'API parlé par un fournisseur.
enum PersonalApiProtocol {
  /// `chat/completions`, le format que la plupart des fournisseurs imitent.
  openAiCompatible,

  /// `responses`, le format d'OpenAI qui donne accès à ses outils intégrés.
  openAiResponses,

  gemini,

  /// `messages`, le format d'Anthropic : en-tête `x-api-key`, version d'API
  /// explicite, et un flux d'évènements nommés plutôt que des `choices`.
  anthropic,
}

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

  /// Vrai si le fournisseur sait consulter le web de lui-même.
  ///
  /// Nommés un par un, et non par défaut : proposer le mode Recherche à un
  /// moteur qui ne l'a pas laisserait croire à une réponse sourcée qui ne le
  /// serait pas.
  bool get supportsWebSearch =>
      protocol == PersonalApiProtocol.openAiResponses ||
      protocol == PersonalApiProtocol.gemini ||
      protocol == PersonalApiProtocol.anthropic;

  String resolveBaseUrl(String customBaseUrl) {
    if (custom) {
      return customBaseUrl.trim();
    }
    return baseUrl;
  }
}

/// Version de l'API Anthropic, exigée sur chaque requête.
///
/// Figée : c'est ce qui garantit que le format des réponses ne change pas sous
/// l'application. La faire évoluer demande de relire le format des évènements.
const anthropicApiVersion = '2023-06-01';

/// Outil de recherche web d'Anthropic, désigné par sa date de version.
///
/// Anthropic date ses outils plutôt que de les versionner : changer cette
/// valeur change d'outil, et une valeur inconnue fait refuser la requête
/// entière. Elle est donc nommée ici, et non écrite au milieu d'une requête.
const anthropicWebSearchTool = 'web_search_20250305';

const anthropicPersonalApiProvider = PersonalApiProvider(
  id: 'anthropic',
  displayName: 'Anthropic',
  protocol: PersonalApiProtocol.anthropic,
  baseUrl: 'https://api.anthropic.com/v1',
);

const deepSeekPersonalApiProvider = PersonalApiProvider(
  id: 'deepseek',
  displayName: 'DeepSeek',
  protocol: PersonalApiProtocol.openAiCompatible,
  baseUrl: 'https://api.deepseek.com/v1',
);

const openAiPersonalApiProvider = PersonalApiProvider(
  id: 'openai',
  displayName: 'OpenAI',
  protocol: PersonalApiProtocol.openAiResponses,
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
  displayName: 'Google',
  protocol: PersonalApiProtocol.gemini,
  baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
);

const customPersonalApiProvider = PersonalApiProvider(
  id: 'custom',
  displayName: 'Personnalisé',
  protocol: PersonalApiProtocol.openAiCompatible,
  baseUrl: '',
  custom: true,
);

/// Par ordre alphabétique : c'est l'ordre du menu, et le seul qui reste
/// prévisible quand la liste s'allonge.
///
/// « Personnalisé » fait exception et reste en dernier : ce n'est pas un
/// fournisseur parmi les autres, c'est celui qu'on choisit quand aucun ne
/// convient. Sa place est au bout de la liste, pas au milieu.
const personalApiProviders = <PersonalApiProvider>[
  anthropicPersonalApiProvider,
  deepSeekPersonalApiProvider,
  geminiPersonalApiProvider,
  groqPersonalApiProvider,
  mistralPersonalApiProvider,
  openAiPersonalApiProvider,
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

/// Attente maximale de la liste des modèles d'un fournisseur.
const modelsTimeout = Duration(seconds: 30);

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

  final baseUrl = normalizeBaseUrl(provider.resolveBaseUrl(customBaseUrl));
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
    } else if (provider.protocol == PersonalApiProtocol.anthropic) {
      // Anthropic n'utilise pas `Authorization` et exige la version d'API sur
      // chaque appel, sans quoi il répond 400.
      headers['x-api-key'] = key;
      headers['anthropic-version'] = anthropicApiVersion;
      uri = uri.replace(queryParameters: <String, String>{'limit': '1000'});
    } else {
      headers['Authorization'] = 'Bearer $key';
      if (provider.id == openRouterPersonalApiProvider.id) {
        uri = uri.replace(
          queryParameters: <String, String>{'output_modalities': 'text'},
        );
      }
    }

    // Même raison que pour la génération : sans délai, un fournisseur qui
    // accepte la connexion puis se tait laisse l'écran des réglages sur son
    // rond indéfiniment. La liste des modèles est un appel court, le délai
    // peut donc l'être aussi.
    final response = await httpClient
        .get(uri, headers: headers)
        .timeout(
          modelsTimeout,
          onTimeout: () => throw PersonalApiTimeoutException(
            '${provider.displayName} n’a pas répondu dans les '
            '${modelsTimeout.inSeconds} secondes.',
          ),
        );
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

    final rawModels =
        provider.id == xAiPersonalApiProvider.id ||
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
      // Anthropic ne publie sur ce point d'entrée que des modèles de
      // conversation : filtrer ne ferait qu'en cacher de nouveaux.
      provider.protocol == PersonalApiProtocol.anthropic ||
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
