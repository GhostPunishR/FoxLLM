// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foxgpt/core/llm/chat_message.dart';
import 'package:foxgpt/features/chat/chat_conversation.dart';
import 'package:foxgpt/features/chat/conversation_store.dart';

void main() {
  late Directory tempDirectory;
  late ConversationStore store;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('foxgpt-chats-');
    store = ConversationStore(
      applicationSupportDirectory: () async => tempDirectory,
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  ChatConversation conversation({
    int id = 1,
    String title = 'Première question',
    DateTime? updatedAt,
    List<ChatMessage>? messages,
  }) {
    return ChatConversation(
      id: id,
      title: title,
      updatedAt: updatedAt ?? DateTime(2026, 9, 13, 10),
      messages:
          messages ??
          <ChatMessage>[
            const ChatMessage.user('Bonjour'),
            const ChatMessage.assistant('Salut !'),
          ],
    );
  }

  test('un historique vide se lit sans fichier', () async {
    expect(await store.load(), isEmpty);
  });

  test('les conversations survivent à un cycle écriture/lecture', () async {
    await store.save(<ChatConversation>[conversation()]);

    final restored = await store.load();
    expect(restored, hasLength(1));
    expect(restored.single.id, 1);
    expect(restored.single.title, 'Première question');
    expect(restored.single.updatedAt, DateTime(2026, 9, 13, 10));
    expect(restored.single.messages.map((m) => m.content), <String>[
      'Bonjour',
      'Salut !',
    ]);
    expect(restored.single.messages.map((m) => m.role), <ChatRole>[
      ChatRole.user,
      ChatRole.assistant,
    ]);
  });

  test('la plus récente arrive en tête', () async {
    await store.save(<ChatConversation>[
      conversation(id: 1, title: 'Ancienne', updatedAt: DateTime(2026, 9, 1)),
      conversation(id: 2, title: 'Récente', updatedAt: DateTime(2026, 9, 12)),
    ]);

    final restored = await store.load();
    expect(restored.map((c) => c.title), <String>['Récente', 'Ancienne']);
  });

  test('l’historique est borné aux plus récentes', () async {
    await store.save(<ChatConversation>[
      for (var i = 0; i < ConversationStore.maxConversations + 25; i++)
        conversation(id: i, title: 'Conversation $i'),
    ]);

    expect(await store.load(), hasLength(ConversationStore.maxConversations));
  });

  test('un fichier corrompu ne bloque pas l’ouverture du chat', () async {
    final file = File(
      '${tempDirectory.path}${Platform.pathSeparator}conversations.json',
    );
    await file.writeAsString('{ ceci n’est pas du JSON');

    expect(await store.load(), isEmpty);
  });

  test('une entrée illisible est ignorée sans perdre les autres', () async {
    final file = File(
      '${tempDirectory.path}${Platform.pathSeparator}conversations.json',
    );
    await file.writeAsString(
      jsonEncode(<String, Object?>{
        'conversations': <Object?>[
          'pas un objet',
          <String, Object?>{'id': 'identifiant invalide'},
          <String, Object?>{
            'id': 7,
            'title': 'Valide',
            'updatedAt': DateTime(2026, 9, 13).toIso8601String(),
            'messages': <Object?>[
              <String, Object?>{'role': 'user', 'content': 'Bonjour'},
              <String, Object?>{'role': 'inconnu', 'content': 'ignoré'},
            ],
          },
        ],
      }),
    );

    final restored = await store.load();
    expect(restored, hasLength(1));
    expect(restored.single.title, 'Valide');
    expect(restored.single.messages.map((m) => m.content), <String>['Bonjour']);
  });

  test('des enregistrements concurrents ne se corrompent pas', () async {
    await Future.wait<void>(<Future<void>>[
      for (var i = 0; i < 12; i++)
        store.save(<ChatConversation>[
          conversation(id: i, title: 'Écriture $i'),
        ]),
    ]);

    final restored = await store.load();
    expect(restored, hasLength(1));
    expect(restored.single.title, startsWith('Écriture '));
    // Aucun fichier temporaire ne doit subsister.
    final leftovers = await tempDirectory
        .list()
        .where((entity) => entity.path.endsWith('.part'))
        .length;
    expect(leftovers, 0);
  });

  test('clear efface l’historique', () async {
    await store.save(<ChatConversation>[conversation()]);
    await store.clear();
    expect(await store.load(), isEmpty);
  });
}
