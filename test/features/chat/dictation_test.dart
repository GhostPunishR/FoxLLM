// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/theme/fox_theme.dart';
import 'package:foxllm/features/chat/chat_screen.dart';
import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/features/chat/conversations/conversation_store.dart';
import 'package:foxllm/features/chat/dictation.dart';
import 'package:foxllm/llm/backend/local_backend_provider.dart';
import 'package:foxllm/llm/backend/local_llm_backend.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm_native/foxllm_native.dart';

void main() {
  testWidgets('le micro cède la place à Envoyer dès qu’on écrit', (
    tester,
  ) async {
    await _pumpChat(tester, _FakeDictation());

    expect(find.byTooltip('Maintenir pour dicter'), findsOneWidget);
    expect(find.byTooltip('Envoyer'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'Traduis');
    await tester.pump();

    // Le micro et l'envoi se relaient au même endroit : à aucun moment le
    // composeur ne porte plus de deux boutons.
    expect(find.byTooltip('Envoyer'), findsOneWidget);
    expect(find.byTooltip('Maintenir pour dicter'), findsNothing);

    // Effacer le brouillon rend le micro.
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();

    expect(find.byTooltip('Maintenir pour dicter'), findsOneWidget);
    expect(find.byTooltip('Envoyer'), findsNothing);
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

  testWidgets('le bouton tient jusqu’au relâchement', (tester) async {
    final dictation = _FakeDictation();
    await _pumpChat(tester, dictation);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('Maintenir pour dicter')),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // La parole remplit le champ. Si le brouillon l'emportait, le bouton
    // deviendrait Envoyer sous le doigt et le relâchement ne serait jamais
    // reçu : la dictée continuerait, micro ouvert, sans plus rien pour
    // l'arrêter.
    dictation.emit('Bonjour');
    await tester.pump();

    expect(find.byTooltip('Dictée en cours'), findsOneWidget);
    expect(find.byTooltip('Envoyer'), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(dictation.listening, isFalse);
    expect(find.byTooltip('Envoyer'), findsOneWidget);
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

  testWidgets('relâcher pendant la préparation n’ouvre pas le micro', (
    tester,
  ) async {
    final dictation = _FakeDictation()..holdInitialize = true;
    await _pumpChat(tester, dictation);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('Maintenir pour dicter')),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    // L'initialisation n'est pas revenue : le micro n'est pas encore ouvert,
    // et c'est exactement le moment où le relâchement doit compter.
    expect(dictation.listening, isFalse);
    await gesture.up();
    await tester.pump();

    dictation.releaseInitialize();
    await tester.pumpAndSettle();

    expect(
      dictation.listening,
      isFalse,
      reason: 'l’écoute s’ouvrait après le relâchement',
    );
    // Rien à annoncer : l'utilisateur a lui-même relâché.
    expect(find.textContaining('besoin du micro'), findsNothing);
    expect(find.textContaining('Aucune reconnaissance'), findsNothing);
    expect(find.text('Parle, je t’écoute…'), findsNothing);
  });

  testWidgets('quitter l’écran pendant la préparation n’ouvre pas le micro', (
    tester,
  ) async {
    final dictation = _FakeDictation()..holdInitialize = true;
    await _pumpChat(tester, dictation);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('Maintenir pour dicter')),
    );
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    dictation.releaseInitialize();
    await tester.pumpAndSettle();

    expect(dictation.listening, isFalse);
    expect(tester.takeException(), isNull);
  });

  group('service réel', _serviceTests);
}

/// Le service réel, sans micro : la plateforme est absente du banc, donc
/// `initialize()` échoue. Ce qui se vérifie ici est l'ordre des décisions, et
/// non la reconnaissance elle-même.
void _serviceTests() {
  test('un arrêt pendant la préparation annule le démarrage', () async {
    final dictation = Dictation();

    final pending = dictation.start(onText: (_) {});
    // Le relâchement arrive avant que l'initialisation ne revienne. L'ancien
    // garde sur `isListening` ne voyait alors rien à arrêter.
    await dictation.stop();

    expect(await pending, DictationStatus.cancelled);
    expect(dictation.isListening, isFalse);
  });

  test('sans arrêt, l’échec de préparation est bien signalé', () async {
    final dictation = Dictation();

    expect(
      await dictation.start(onText: (_) {}),
      DictationStatus.unavailable,
      reason: 'une annulation ne doit pas masquer une vraie panne',
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

  /// Vanne : le test décide quand l'initialisation revient, pour reproduire
  /// un relâchement survenu pendant la préparation.
  bool holdInitialize = false;
  final _initGate = Completer<void>();
  int _epoch = 0;

  void releaseInitialize() => _initGate.complete();

  @override
  bool get isListening => listening;

  @override
  Future<DictationStatus> start({
    required void Function(String text) onText,
    String localeId = 'fr_FR',
  }) async {
    final epoch = ++_epoch;
    if (holdInitialize) {
      await _initGate.future;
    }
    if (epoch != _epoch) {
      return DictationStatus.cancelled;
    }
    if (status != DictationStatus.listening) {
      return status;
    }
    listening = true;
    _onText = onText;
    return status;
  }

  void emit(String text) => _onText?.call(text);

  @override
  Future<void> stop() async {
    _epoch += 1;
    listening = false;
  }
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
  }) => Stream<String>.value('ok');

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
