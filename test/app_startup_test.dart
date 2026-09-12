import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxgpt/core/llm/chat_message.dart';
import 'package:foxgpt/core/llm/generation_settings.dart';
import 'package:foxgpt/core/llm/local_backend_provider.dart';
import 'package:foxgpt/core/llm/local_llm_backend.dart';
import 'package:foxgpt/features/chat/chat_screen.dart';
import 'package:foxgpt/main.dart';
import 'package:foxgpt_native/foxgpt_native.dart';

void main() {
  testWidgets('ouvre directement le chat, sans écran intermédiaire', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [localLlmBackendProvider.overrideWithValue(_IdleBackend())],
        child: const FoxGptApp(),
      ),
    );

    // Une seule frame, sans avancer l'horloge : le chat doit déjà être là.
    // L'ancien splash Flutter imposait 700 ms d'animation avant d'y arriver.
    await tester.pump();

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('Message ou maintenir pour parler'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _IdleBackend implements LocalLlmBackend {
  @override
  String get id => 'idle';

  @override
  String get displayName => 'Backend de test';

  @override
  String? get loadedModelPath => null;

  @override
  Future<String> get nativeVersion async => 'idle/0.0.0';

  @override
  Future<bool> get isModelLoaded async => false;

  @override
  Future<FoxGptModelInfo?> get modelInfo async => null;

  @override
  Future<FoxGptGenerationStats?> get lastGenerationStats async => null;

  @override
  Future<void> loadModel(String path) async {}

  @override
  Future<void> unloadModel() async {}

  @override
  Stream<String> generate({
    required List<ChatMessage> messages,
    GenerationSettings settings = const GenerationSettings(),
  }) => const Stream<String>.empty();

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
