// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxgpt/core/llm/chat_message.dart';
import 'package:foxgpt/core/llm/generation_settings.dart';
import 'package:foxgpt/core/llm/local_backend_provider.dart';
import 'package:foxgpt/core/llm/local_llm_backend.dart';
import 'package:foxgpt/core/theme/fox_theme.dart';
import 'package:foxgpt/features/chat/chat_conversation.dart';
import 'package:foxgpt/features/chat/chat_screen.dart';
import 'package:foxgpt/features/chat/conversation_store.dart';
import 'package:foxgpt/features/chat/dictation.dart';
import 'package:foxgpt_native/foxgpt_native.dart';

void main() {
  testWidgets('le micro reste offert, brouillon vide ou non', (tester) async {
    await _pumpChat(tester, _FakeDictation());

    expect(find.byTooltip('Maintenir pour dicter'), findsOneWidget);
    expect(find.byTooltip('Envoyer'), findsNothing);

    // Dicter la fin d'une phrase déjà commencée doit rester possible.
    await tester.enterText(find.byType(TextField).first, 'Traduis');
    await tester.pump();

    expect(find.byTooltip('Maintenir pour dicter'), findsOneWidget);
    expect(find.byTooltip('Envoyer'), findsOneWidget);
  });

  testWidgets('un appui simple rappelle qu’il faut maintenir', (tester) async {
    await _pumpChat(tester, _FakeDictation());

    await tester.tap(find.byTooltip('Maintenir pour dicter'));
    await tester.pumpAndSettle();

    expect(
      find.text('Maintiens le bouton du micro pour dicter.'),
      findsOneWidget,
    );
  });

  testWidgets('maintenir écrit la parole dans le champ', (tester) async {
    final dictation = _FakeDictation();
    await _pumpChat(tester, dictation);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('Maintenir pour dicter')),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(dictation.listening, isTrue);
    expect(find.text('Parle, je t’écoute…'), findsOneWidget);

    // Chaque résultat partiel remplace le précédent.
    dictation.emit('Bonjour');
    await tester.pump();
    dictation.emit('Bonjour tout le monde');
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'Bonjour tout le monde');

    await gesture.up();
    await tester.pumpAndSettle();

    expect(dictation.listening, isFalse);
    // Le texte reste modifiable avant envoi : rien ne part tout seul.
    expect(field.controller!.text, 'Bonjour tout le monde');
    expect(find.byTooltip('Envoyer'), findsOneWidget);
  });

  testWidgets('la parole s’ajoute au brouillon déjà saisi', (tester) async {
    final dictation = _FakeDictation();
    await _pumpChat(tester, dictation);

    await tester.enterText(find.byType(TextField).first, 'Traduis');
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('Maintenir pour dicter')),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    dictation.emit('cette phrase');
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'Traduis cette phrase');
  });

  testWidgets('un micro refusé est expliqué', (tester) async {
    await _pumpChat(tester, _FakeDictation(status: DictationStatus.denied));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('Maintenir pour dicter')),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.textContaining('besoin du micro'), findsOneWidget);
    expect(find.text('Parle, je t’écoute…'), findsNothing);
  });

  testWidgets('un appareil sans reconnaissance vocale le dit', (tester) async {
    await _pumpChat(
      tester,
      _FakeDictation(status: DictationStatus.unavailable),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('Maintenir pour dicter')),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      find.text('Aucune reconnaissance vocale disponible sur cet appareil.'),
      findsOneWidget,
    );
  });
}

Future<void> _pumpChat(WidgetTester tester, Dictation dictation) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dictationProvider.overrideWithValue(dictation),
        conversationStoreProvider.overrideWithValue(_EmptyStore()),
        localLlmBackendProvider.overrideWithValue(_IdleBackend()),
      ],
      child: MaterialApp(
        theme: FoxTheme.light.themeData,
        home: const ChatScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Reconnaissance simulée : les tests disent quand la parole arrive.
class _FakeDictation implements Dictation {
  _FakeDictation({this.status = DictationStatus.listening});

  final DictationStatus status;
  bool listening = false;
  void Function(String text)? _onText;

  @override
  bool get isListening => listening;

  @override
  Future<DictationStatus> start({
    required void Function(String text) onText,
    String localeId = 'fr_FR',
  }) async {
    if (status != DictationStatus.listening) {
      return status;
    }
    listening = true;
    _onText = onText;
    return status;
  }

  void emit(String text) => _onText?.call(text);

  @override
  Future<void> stop() async => listening = false;
}

class _EmptyStore implements ConversationStore {
  @override
  Future<List<ChatConversation>> load() async => <ChatConversation>[];

  @override
  Future<void> save(List<ChatConversation> conversations) async {}

  @override
  Future<void> clear() async {}
}

class _IdleBackend implements LocalLlmBackend {
  @override
  String get id => 'idle';

  @override
  String get displayName => 'Backend de test';

  @override
  String? get loadedModelPath => '/models/test.gguf';

  @override
  Future<String> get nativeVersion async => 'idle/0.0.0';

  @override
  Future<bool> get isModelLoaded async => true;

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
  }) => Stream<String>.value('ok');

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
