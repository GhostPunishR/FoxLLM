// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/features/chat/attachments/attachment_store.dart';
import 'package:foxllm/features/chat/chat_screen.dart';
import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/features/chat/conversations/conversation_store.dart';
import 'package:foxllm/llm/backend/local_backend_provider.dart';
import 'package:foxllm/llm/backend/local_llm_backend.dart';
import 'package:foxllm/llm/model/chat_attachment.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm_native/foxllm_native.dart';

import '../../../support/localized_app.dart';

void main() {
  group('pièces jointes d’une conversation', () {
    test('une version conservée compte autant que le fil visible', () {
      // Le défaut : la suppression ne parcourait que `messages`. Les copies
      // citées par la seule version conservée restaient sur le disque, sans
      // que plus rien ne puisse les rouvrir ni les effacer.
      final conversation = ChatConversation(
        id: 1,
        title: 'Deux versions',
        updatedAt: DateTime(2026, 9, 19),
        messages: <ChatMessage>[
          ChatMessage(
            role: ChatRole.user,
            content: 'Voici',
            attachments: <ChatAttachment>[_attachment('visible.png')],
          ),
        ],
        previousMessages: <ChatMessage>[
          ChatMessage(
            role: ChatRole.user,
            content: 'Voici',
            attachments: <ChatAttachment>[_attachment('visible.png')],
          ),
          ChatMessage(
            role: ChatRole.user,
            content: 'Et aussi',
            attachments: <ChatAttachment>[_attachment('conservee.png')],
          ),
        ],
      );

      expect(
        conversation.attachments.map((a) => a.path),
        containsAll(<String>['/tmp/visible.png', '/tmp/conservee.png']),
      );
    });

    test('sans version conservée, seul le fil compte', () {
      final conversation = ChatConversation(
        id: 2,
        title: 'Une seule',
        updatedAt: DateTime(2026, 9, 19),
        messages: <ChatMessage>[
          ChatMessage(
            role: ChatRole.user,
            content: 'Voici',
            attachments: <ChatAttachment>[_attachment('seule.png')],
          ),
        ],
      );

      expect(conversation.attachments.map((a) => a.path), <String>[
        '/tmp/seule.png',
      ]);
    });
  });

  testWidgets('supprimer efface aussi les copies de la version conservée', (
    tester,
  ) async {
    final attachments = _RecordingAttachmentStore();
    final store = _SeededStore(<ChatConversation>[
      ChatConversation(
        id: 7,
        title: 'À supprimer',
        updatedAt: DateTime(2026, 9, 19),
        messages: <ChatMessage>[
          ChatMessage(
            role: ChatRole.user,
            content: 'Question',
            attachments: <ChatAttachment>[_attachment('visible.png')],
          ),
        ],
        previousMessages: <ChatMessage>[
          ChatMessage(
            role: ChatRole.user,
            content: 'Question',
            attachments: <ChatAttachment>[_attachment('conservee.png')],
          ),
        ],
      ),
    ]);

    await _pumpChat(tester, store, attachments);

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Actions de la conversation').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await tester.pumpAndSettle();

    expect(
      attachments.deleted,
      containsAll(<String>['/tmp/visible.png', '/tmp/conservee.png']),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('au delà du plafond, les plus anciennes partent pour de bon', (
    tester,
  ) async {
    // `ConversationStore` n'enregistre que les cent premières. Sans ménage,
    // les suivantes restaient à l'écran puis disparaissaient au lancement
    // suivant, en laissant leurs pièces jointes derrière elles.
    final attachments = _RecordingAttachmentStore();
    final store = _SeededStore(<ChatConversation>[
      for (var index = 0; index < ConversationStore.maxConversations; index++)
        ChatConversation(
          id: 1000 + index,
          title: 'Conversation $index',
          updatedAt: DateTime(2026, 9, 19).subtract(Duration(days: index)),
          messages: <ChatMessage>[
            ChatMessage(
              role: ChatRole.user,
              content: 'Message $index',
              attachments: index == ConversationStore.maxConversations - 1
                  ? <ChatAttachment>[_attachment('la-plus-vieille.png')]
                  : const <ChatAttachment>[],
            ),
          ],
        ),
    ]);

    await _pumpChat(tester, store, attachments);
    expect(store.loaded.length, ConversationStore.maxConversations);

    await tester.enterText(find.byType(TextField).first, 'Une de plus');
    await tester.pump();
    await tester.tap(find.byTooltip('Envoyer'));
    await tester.pumpAndSettle();

    expect(
      store.lastSaved.length,
      ConversationStore.maxConversations,
      reason: 'le plafond doit être tenu en mémoire, pas seulement au fichier',
    );
    expect(
      store.lastSaved.map((conversation) => conversation.title),
      isNot(contains('Conversation 99')),
      reason: 'la plus ancienne devait céder la place',
    );
    expect(
      attachments.deleted,
      contains('/tmp/la-plus-vieille.png'),
      reason: 'ses copies ne sont plus citées par personne',
    );
  });
}

ChatAttachment _attachment(String name) => ChatAttachment(
  name: name,
  path: '/tmp/$name',
  mimeType: 'image/png',
  sizeBytes: 4,
);

Future<void> _pumpChat(
  WidgetTester tester,
  _SeededStore store,
  _RecordingAttachmentStore attachments,
) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localLlmBackendProvider.overrideWithValue(_FakeBackend()),
        conversationStoreProvider.overrideWithValue(store),
        attachmentStoreProvider.overrideWithValue(attachments),
      ],
      child: localizedApp(home: ChatScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

class _SeededStore implements ConversationStore {
  _SeededStore(this.loaded);

  final List<ChatConversation> loaded;
  List<ChatConversation> lastSaved = <ChatConversation>[];

  @override
  Future<List<ChatConversation>> load() async => loaded;

  @override
  Future<void> save(List<ChatConversation> conversations) async {
    lastSaved = List<ChatConversation>.of(conversations);
  }

  @override
  Future<void> clear() async => lastSaved = <ChatConversation>[];
}

class _RecordingAttachmentStore implements AttachmentStore {
  final List<String> deleted = <String>[];

  @override
  Future<void> delete(Iterable<ChatAttachment> attachments) async {
    deleted.addAll(attachments.map((attachment) => attachment.path));
  }

  @override
  Future<ChatAttachment> save({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) async => _attachment(name);

  @override
  Future<Uint8List?> read(ChatAttachment attachment) async => null;
}

class _FakeBackend implements LocalLlmBackend {
  /// Le moteur local dit désormais pourquoi il s’est arrêté ; ce double
  /// n’a rien à écourter.
  @override
  String? get incompleteReason => null;

  @override
  String get id => 'fake';

  @override
  String get displayName => 'Backend de test';

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
  }) => Stream<String>.value('Réponse');

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
