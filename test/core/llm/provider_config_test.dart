// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:foxgpt/core/llm/provider_config.dart';

void main() {
  group('normalizeBaseUrl', () {
    test('retire les espaces et toutes les barres finales', () {
      expect(
        normalizeBaseUrl('https://api.example.com/v1'),
        'https://api.example.com/v1',
      );
      expect(
        normalizeBaseUrl('  https://api.example.com/v1  '),
        'https://api.example.com/v1',
      );
      expect(
        normalizeBaseUrl('https://api.example.com/v1/'),
        'https://api.example.com/v1',
      );
      expect(
        normalizeBaseUrl('https://api.example.com/v1//'),
        'https://api.example.com/v1',
      );
      expect(
        normalizeBaseUrl('https://api.example.com/v1///'),
        'https://api.example.com/v1',
      );
    });

    test('laisse une valeur vide inchangée', () {
      expect(normalizeBaseUrl(''), '');
      expect(normalizeBaseUrl('   '), '');
    });
  });

  group('ProviderConfig.chatCompletionsUri', () {
    ProviderConfig configWith(String baseUrl) => ProviderConfig(
      id: 'test',
      displayName: 'Test',
      baseUrl: baseUrl,
      model: 'test-model',
    );

    test('construit une URL sans double séparateur', () {
      expect(
        configWith('https://api.example.com/v1').chatCompletionsUri.toString(),
        'https://api.example.com/v1/chat/completions',
      );
      expect(
        configWith('https://api.example.com/v1/').chatCompletionsUri.toString(),
        'https://api.example.com/v1/chat/completions',
      );
      // Une base URL collée depuis une documentation peut porter plusieurs
      // barres finales : elles produisaient auparavant `/v1//chat/completions`.
      expect(
        configWith(
          'https://api.example.com/v1//',
        ).chatCompletionsUri.toString(),
        'https://api.example.com/v1/chat/completions',
      );
    });
  });
}
