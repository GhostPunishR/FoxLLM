// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/llm/personal_api_provider.dart';
import 'package:foxllm/core/llm/personal_api_settings.dart';

void main() {
  group('PersonalApiSettings', () {
    test('uses the preset URL for known providers', () {
      const configured = PersonalApiSettings(
        providerId: 'openai',
        model: 'example-model',
        hasApiKey: true,
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
      );
      expect(configuredCustom.isConfigured, isTrue);
    });

    test('resolves every built-in provider', () {
      expect(personalApiProviderById('openai').displayName, 'OpenAI');
      expect(personalApiProviderById('gemini').displayName, 'Google Gemini');
      expect(personalApiProviderById('groq').displayName, 'Groq');
      expect(personalApiProviderById('mistral').displayName, 'Mistral AI');
      expect(personalApiProviderById('openrouter').displayName, 'OpenRouter');
      expect(personalApiProviderById('xai').displayName, 'xAI');
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
        describePersonalApiError(error),
        'Aucun crédit API disponible pour le compte lié à cette clé.',
      );
    });
  });
}
