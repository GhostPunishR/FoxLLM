class GenerationSettings {
  const GenerationSettings({
    this.temperature = 0.7,
    this.topP = 0.9,
    this.maxTokens = 512,
  });

  final double temperature;
  final double topP;
  final int maxTokens;
}
