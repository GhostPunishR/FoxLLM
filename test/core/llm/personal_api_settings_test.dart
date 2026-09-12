import 'package:flutter_test/flutter_test.dart';
import 'package:foxgpt/core/llm/personal_api_settings.dart';

void main() {
  group('PersonalApiSettings', () {
    test('is configured only with URL, model and key', () {
      const empty = PersonalApiSettings();
      expect(empty.isConfigured, isFalse);

      const configured = PersonalApiSettings(
        baseUrl: 'https://example.com/v1',
        model: 'example-model',
        hasApiKey: true,
      );
      expect(configured.isConfigured, isTrue);
      expect(
        configured.toProviderConfig().chatCompletionsUri.toString(),
        'https://example.com/v1/chat/completions',
      );
    });
  });

  group('isAllowedPersonalApiBaseUrl', () {
    test('accepts HTTPS providers', () {
      expect(
        isAllowedPersonalApiBaseUrl('https://api.example.com/v1'),
        isTrue,
      );
    });

    test('accepts HTTP only for private or loopback hosts', () {
      expect(isAllowedPersonalApiBaseUrl('http://127.0.0.1:11434/v1'), isTrue);
      expect(isAllowedPersonalApiBaseUrl('http://192.168.1.20:8080/v1'), isTrue);
      expect(isAllowedPersonalApiBaseUrl('http://10.0.0.4/v1'), isTrue);
      expect(isAllowedPersonalApiBaseUrl('http://172.16.1.4/v1'), isTrue);
      expect(isAllowedPersonalApiBaseUrl('http://api.example.com/v1'), isFalse);
    });

    test('rejects malformed URLs', () {
      expect(isAllowedPersonalApiBaseUrl('api.example.com/v1'), isFalse);
      expect(isAllowedPersonalApiBaseUrl(''), isFalse);
    });
  });
}
