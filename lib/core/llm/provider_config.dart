enum ApiKeyPersistence { device, session }

class ProviderConfig {
  const ProviderConfig({
    required this.id,
    required this.displayName,
    required this.baseUrl,
    required this.model,
    this.apiKeyPersistence = ApiKeyPersistence.device,
  });

  final String id;
  final String displayName;
  final String baseUrl;
  final String model;
  final ApiKeyPersistence apiKeyPersistence;

  Uri get chatCompletionsUri {
    final normalized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$normalized/chat/completions');
  }
}
