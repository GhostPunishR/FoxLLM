import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxgpt/core/llm/chat_message.dart';
import 'package:foxgpt/core/llm/generation_settings.dart';
import 'package:foxgpt/core/llm/local_backend_provider.dart';
import 'package:foxgpt/core/llm/local_llm_backend.dart';
import 'package:foxgpt/features/chat/chat_screen.dart';
import 'package:foxgpt_native/foxgpt_native.dart';

void main() {
  testWidgets('demande un modèle tant qu’aucun GGUF n’est chargé', (
    tester,
  ) async {
    final backend = _FakeChatBackend(loadedModelPath: null);
    await _pumpChat(tester, backend);

    await _send(tester, 'Bonjour');

    expect(
      find.text('Charge un modèle GGUF avant de discuter.'),
      findsOneWidget,
    );
    expect(backend.generateCalls, isEmpty);
  });

  testWidgets('affiche le message envoyé puis la réponse streamée', (
    tester,
  ) async {
    final backend = _FakeChatBackend(chunks: <String>['Salut ', 'toi !']);
    await _pumpChat(tester, backend);

    await _send(tester, 'Bonjour');
    await tester.pumpAndSettle();

    expect(find.text('Bonjour'), findsOneWidget);
    expect(find.text('Salut toi !'), findsOneWidget);
    // Le backend reçoit l'historique, pas seulement le dernier message brut.
    expect(backend.generateCalls.single.map((m) => m.content), <String>[
      'Bonjour',
    ]);
    expect(backend.generateCalls.single.single.role, ChatRole.user);
    expect(tester.takeException(), isNull);
  });

  testWidgets('transmet tout l’historique à la requête suivante', (
    tester,
  ) async {
    final backend = _FakeChatBackend(chunks: <String>['ok']);
    await _pumpChat(tester, backend);

    await _send(tester, 'Premier');
    await tester.pumpAndSettle();
    await _send(tester, 'Second');
    await tester.pumpAndSettle();

    expect(backend.generateCalls, hasLength(2));
    expect(backend.generateCalls.last.map((m) => m.content), <String>[
      'Premier',
      'ok',
      'Second',
    ]);
    expect(backend.generateCalls.last.map((m) => m.role), <ChatRole>[
      ChatRole.user,
      ChatRole.assistant,
      ChatRole.user,
    ]);
  });

  testWidgets('le bouton Arrêter interrompt la génération en cours', (
    tester,
  ) async {
    final chunks = StreamController<String>();
    final backend = _FakeChatBackend(stream: chunks.stream);
    await _pumpChat(tester, backend);

    await _send(tester, 'Bonjour');
    chunks.add('Je réflé');
    await tester.pump();

    expect(find.byTooltip('Arrêter'), findsOneWidget);
    expect(find.byTooltip('Envoyer'), findsNothing);

    await tester.tap(find.byTooltip('Arrêter'));
    await tester.pump();
    expect(backend.stopCalls, 1);

    await chunks.close();
    await tester.pumpAndSettle();

    // La réponse partielle reste affichée et le composer redevient disponible.
    expect(find.text('Je réflé'), findsOneWidget);
    expect(find.byTooltip('Arrêter'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signale une erreur de génération sans laisser de bulle vide', (
    tester,
  ) async {
    final backend = _FakeChatBackend(
      stream: Stream<String>.error(StateError('moteur indisponible')),
    );
    await _pumpChat(tester, backend);

    await _send(tester, 'Bonjour');
    await tester.pumpAndSettle();

    expect(find.textContaining('Génération impossible'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Bonjour'), findsOneWidget);
    expect(find.byTooltip('Arrêter'), findsNothing);
  });

  testWidgets('une réponse vide ne laisse pas de bulle assistant', (
    tester,
  ) async {
    final backend = _FakeChatBackend(chunks: const <String>[]);
    await _pumpChat(tester, backend);

    await _send(tester, 'Bonjour');
    await tester.pumpAndSettle();

    expect(find.text('Bonjour'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la conversation envoyée apparaît dans le menu latéral', (
    tester,
  ) async {
    final backend = _FakeChatBackend(chunks: <String>['ok']);
    await _pumpChat(tester, backend);

    await _send(tester, 'Ma première question');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();

    expect(find.text('Ma première question'), findsWidgets);
    expect(find.text('Aucune conversation'), findsNothing);
  });
}

Future<void> _pumpChat(WidgetTester tester, _FakeChatBackend backend) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [localLlmBackendProvider.overrideWithValue(backend)],
      child: const MaterialApp(home: ChatScreen()),
    ),
  );
  await tester.pump();
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byTooltip('Envoyer'));
  await tester.pump();
}

/// Backend de test : `LocalLlmBackend` est le contrat que l'écran de chat lit
/// dans Riverpod, y compris quand une API personnelle est active.
class _FakeChatBackend implements LocalLlmBackend {
  _FakeChatBackend({
    this.chunks = const <String>[],
    this.stream,
    this.loadedModelPath = '/models/test.gguf',
  });

  final List<String> chunks;
  final Stream<String>? stream;

  final List<List<ChatMessage>> generateCalls = <List<ChatMessage>>[];
  int stopCalls = 0;

  @override
  final String? loadedModelPath;

  @override
  String get id => 'fake';

  @override
  String get displayName => 'Backend de test';

  @override
  Future<String> get nativeVersion async => 'fake/0.0.0';

  @override
  Future<bool> get isModelLoaded async => loadedModelPath != null;

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
  }) {
    generateCalls.add(List<ChatMessage>.of(messages));
    return stream ?? Stream<String>.fromIterable(chunks);
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  Future<void> dispose() async {}
}
