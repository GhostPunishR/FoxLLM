// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/core/theme/fox_theme.dart';
import 'package:foxllm/features/chat/chat_screen.dart';
import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/features/chat/conversations/conversation_store.dart';
import 'package:foxllm/llm/backend/local_backend_provider.dart';
import 'package:foxllm/llm/backend/local_llm_backend.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm_native/foxllm_native.dart';

import '../../support/localized_app.dart';

/// Une réponse locale coupée au plafond doit le dire.
///
/// C'est le défaut d'origine : le moteur s'arrêtait net au bout de son compte
/// de jetons, au milieu d'une ligne de code, et rien ne distinguait ce texte
/// d'une réponse achevée. Le chat savait déjà afficher la mention, mais aucun
/// moteur local ne la lui donnait.
void main() {
  testWidgets('un plafond de jetons atteint se lit sous la réponse', (
    tester,
  ) async {
    final store = _RecordingStore();
    await _pumpChat(tester, store, _FakeBackend(reason: 'length'));

    await _send(tester, 'Écris-moi du code');

    expect(
      find.text('Réponse écourtée : la limite de longueur a été atteinte.'),
      findsOneWidget,
    );
    final saved = store.saved.last.single.messages.last;
    expect(saved.outcome, GenerationOutcome.incomplete);
    expect(saved.outcomeReason, 'length');
    // Le texte reçu reste affiché : il est partiel, pas faux.
    expect(saved.content, 'du code, coupé net');
  });

  testWidgets('une fenêtre pleine se dit autrement', (tester) async {
    // Le remède diffère : relever la limite n'y changerait rien, c'est la
    // conversation qu'il faut alléger.
    final store = _RecordingStore();
    await _pumpChat(tester, store, _FakeBackend(reason: 'context_length'));

    await _send(tester, 'Une longue conversation');

    expect(
      find.text(
        'Réponse écourtée : la conversation remplit la fenêtre du modèle.',
      ),
      findsOneWidget,
    );
    expect(
      store.saved.last.single.messages.last.outcomeReason,
      'context_length',
    );
  });

  testWidgets('une réponse achevée ne porte aucune mention', (tester) async {
    final store = _RecordingStore();
    await _pumpChat(tester, store, _FakeBackend(reason: null));

    await _send(tester, 'Bonjour');

    expect(find.textContaining('écourtée'), findsNothing);
    expect(
      store.saved.last.single.messages.last.outcome,
      GenerationOutcome.complete,
    );
  });
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump();
  await tester.tap(find.byTooltip('Envoyer'));
  await tester.pumpAndSettle();
}

Future<void> _pumpChat(
  WidgetTester tester,
  _RecordingStore store,
  _FakeBackend backend,
) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localLlmBackendProvider.overrideWithValue(backend),
        conversationStoreProvider.overrideWithValue(store),
      ],
      child: localizedApp(
        theme: FoxTheme.light.themeData,
        home: const ChatScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _RecordingStore implements ConversationStore {
  final List<List<ChatConversation>> saved = <List<ChatConversation>>[];

  @override
  Future<List<ChatConversation>> load() async => const <ChatConversation>[];

  @override
  Future<void> save(List<ChatConversation> conversations) async =>
      saved.add(conversations);

  @override
  Future<void> clear() async {}
}

/// Un moteur local qui rend un texte puis annonce pourquoi il s'est arrêté,
/// exactement comme le vrai le fait depuis le relevé du moteur natif.
class _FakeBackend implements LocalLlmBackend {
  _FakeBackend({required this.reason});

  final String? reason;

  @override
  String? incompleteReason;

  @override
  String get id => 'local';

  @override
  String get displayName => 'Modèle local';

  @override
  String? get loadedModelPath => '/models/test.gguf';

  @override
  Future<String> get nativeVersion async => 'fake/0.0.0';

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
  }) async* {
    incompleteReason = null;
    yield 'du code, coupé net';
    // Le motif est posé avant la fermeture du flux, comme le vrai moteur le
    // fait depuis le relevé qui suit la génération.
    incompleteReason = reason;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
