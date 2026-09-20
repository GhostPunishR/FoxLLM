// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/storage/api_key_store.dart';
import 'package:foxllm/l10n/app_localizations.dart';
import 'package:foxllm/llm/backend/anthropic_backend.dart';
import 'package:foxllm/llm/backend/gemini_backend.dart';
import 'package:foxllm/llm/backend/llm_backend.dart';
import 'package:foxllm/llm/backend/local_engine_error.dart';
import 'package:foxllm/llm/backend/openai_compatible_backend.dart';
import 'package:foxllm/llm/backend/openai_responses_backend.dart';
import 'package:foxllm/llm/personal_api/personal_api_provider.dart';
import 'package:foxllm/llm/personal_api/personal_api_settings.dart';

/// Les traductions, sans arbre de widgets : ce banc n'en monte aucun.
final _l10n = lookupAppLocalizations(const Locale('fr'));

void main() {
  group('PersonalApiSettings', () {
    test('uses the preset URL for known providers', () {
      const configured = PersonalApiSettings(
        providerId: 'openai',
        model: 'example-model',
        hasApiKey: true,
        apiKeyDestination: 'https://api.openai.com:443/v1',
      );

      expect(configured.isConfigured, isTrue);
      expect(configured.effectiveBaseUrl, 'https://api.openai.com/v1');
      expect(
        configured.toProviderConfig().chatCompletionsUri.toString(),
        'https://api.openai.com/v1/chat/completions',
      );
    });

    test('requires a custom URL for a custom provider', () {
      const emptyCustom = PersonalApiSettings(
        providerId: 'custom',
        model: 'example-model',
        hasApiKey: true,
      );
      expect(emptyCustom.isConfigured, isFalse);

      const configuredCustom = PersonalApiSettings(
        providerId: 'custom',
        baseUrl: 'https://example.com/v1',
        model: 'example-model',
        hasApiKey: true,
        apiKeyDestination: 'https://example.com:443/v1',
      );
      expect(configuredCustom.isConfigured, isTrue);
    });

    test('resolves every built-in provider', () {
      expect(personalApiProviderById('anthropic').displayName, 'Anthropic');
      expect(personalApiProviderById('deepseek').displayName, 'DeepSeek');
      expect(personalApiProviderById('openai').displayName, 'OpenAI');
      expect(personalApiProviderById('gemini').displayName, 'Google');
      expect(personalApiProviderById('groq').displayName, 'Groq');
      expect(personalApiProviderById('mistral').displayName, 'Mistral AI');
      expect(personalApiProviderById('openrouter').displayName, 'OpenRouter');
      expect(personalApiProviderById('custom').displayName, 'Personnalisé');
      expect(personalApiProviderById('xai').displayName, 'xAI');
    });

    test('chaque fournisseur reçoit l’adaptateur de son protocole', () {
      LlmBackend backendFor(String providerId) {
        final backend = createPersonalApiRemoteBackend(
          settings: PersonalApiSettings(
            providerId: providerId,
            model: 'modele',
            hasApiKey: true,
          ),
          keyStore: ApiKeyStore(),
        );
        addTearDown(backend.dispose);
        return backend;
      }

      expect(backendFor('anthropic'), isA<AnthropicBackend>());
      expect(backendFor('deepseek'), isA<OpenAiCompatibleBackend>());
      expect(backendFor('openai'), isA<OpenAiResponsesBackend>());
      expect(backendFor('gemini'), isA<GeminiBackend>());
    });
  });

  group('isAllowedPersonalApiBaseUrl', () {
    test('accepts HTTPS providers', () {
      expect(isAllowedPersonalApiBaseUrl('https://api.example.com/v1'), isTrue);
    });

    test('accepts HTTP only for private or loopback hosts', () {
      expect(isAllowedPersonalApiBaseUrl('http://127.0.0.1:11434/v1'), isTrue);
      expect(
        isAllowedPersonalApiBaseUrl('http://192.168.1.20:8080/v1'),
        isTrue,
      );
      expect(isAllowedPersonalApiBaseUrl('http://10.0.0.4/v1'), isTrue);
      expect(isAllowedPersonalApiBaseUrl('http://172.16.1.4/v1'), isTrue);
      expect(isAllowedPersonalApiBaseUrl('http://api.example.com/v1'), isFalse);
    });

    test('rejects malformed URLs', () {
      expect(isAllowedPersonalApiBaseUrl('api.example.com/v1'), isFalse);
      expect(isAllowedPersonalApiBaseUrl(''), isFalse);
    });
  });

  group('describePersonalApiError', () {
    test('turns exhausted credits into a readable message', () {
      const error = PersonalApiHttpException(
        statusCode: 429,
        body:
            '{"error":{"message":"You have no credits remaining.",'
            '"type":"insufficient_quota","code":"credit_balance_exhausted"}}',
      );

      expect(
        describePersonalApiError(error, _l10n),
        'Aucun crédit API disponible pour le compte lié à cette clé.',
      );
    });

    test('traduit les refus du moteur local', () {
      // Le pont natif lève un `StateError` portant le message anglais écrit
      // dans le C++. Il remontait tel quel jusqu'au bandeau du chat, alors que
      // c'est le refus le plus fréquent avec un modèle local.
      final error = StateError(LocalEngineFailure.contextFull.nativeMessage);

      final described = describePersonalApiError(error, _l10n);
      expect(described, isNot(contains('Prompt exceeds')));
      expect(described, contains('contexte'));
    });

    test('un StateError qui ne vient pas du moteur garde son message', () {
      // Tout ne passe pas par le pont : un état incohérent côté Dart porte
      // déjà un message français, qu'il ne faut pas remplacer.
      final error = StateError('Le fournisseur a répondu sans contenu texte.');

      expect(
        describePersonalApiError(error, _l10n),
        'Le fournisseur a répondu sans contenu texte.',
      );
    });

    test('et la même erreur se lit en anglais dans l’autre langue', () {
      final error = StateError(LocalEngineFailure.contextFull.nativeMessage);
      final english = lookupAppLocalizations(const Locale('en'));

      expect(
        describePersonalApiError(error, english),
        contains('context window'),
      );
    });
  });
}
