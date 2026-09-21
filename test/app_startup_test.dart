// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/features/chat/chat_screen.dart';
import 'package:foxllm/llm/backend/local_backend_provider.dart';
import 'package:foxllm/llm/backend/local_llm_backend.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm/core/l10n/fox_language.dart';
import 'package:foxllm/core/l10n/language_provider.dart';
import 'package:foxllm/main.dart';
import 'package:foxllm_native/foxllm_native.dart';

void main() {
  testWidgets('ouvre directement le chat, sans écran intermédiaire', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localLlmBackendProvider.overrideWithValue(_IdleBackend()),
          foxLanguageProvider.overrideWith(_FrenchLanguage.new),
        ],
        child: const FoxLlmApp(),
      ),
    );

    // Une seule frame, sans avancer l'horloge : le chat doit déjà être là.
    // L'ancien splash Flutter imposait 700 ms d'animation avant d'y arriver.
    await tester.pump();

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('Demander à FoxLLM'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ne construit pas le moteur local avant le premier frame', (
    tester,
  ) async {
    // Construire `LocalLlmBackend` démarre l'isolate worker et charge
    // `libfoxllm_native.so`, donc `llama.cpp`. Fait pendant le premier build,
    // ce travail retarde l'affichage du chat d'autant. Le moteur ne doit être
    // créé qu'à la première utilisation réelle.
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var backendsCreated = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localLlmBackendProvider.overrideWith((ref) {
            backendsCreated += 1;
            return _IdleBackend();
          }),
        ],
        child: const FoxLlmApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(backendsCreated, 0);

    // La première utilisation réelle le construit bien, une seule fois.
    final element = tester.element(find.byType(ChatScreen));
    final container = ProviderScope.containerOf(element);
    container.read(localLlmBackendProvider);
    container.read(localLlmBackendProvider);
    expect(backendsCreated, 1);
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
  Future<FoxLlmModelInfo?> get modelInfo async => null;

  @override
  Future<FoxLlmGenerationStats?> get lastGenerationStats async => null;

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

/// Fige la langue sur le français.
///
/// Ce banc monte la vraie application, qui suit la langue de l'appareil : sans
/// cela il chercherait « Demander à FoxLLM » sur une machine d'intégration
/// continue anglophone, qui affiche « Ask FoxLLM ». La langue du banc doit
/// venir du banc, jamais de la machine qui l'exécute.
class _FrenchLanguage extends FoxLanguageController {
  @override
  FoxLanguage build() => FoxLanguage.french;
}
