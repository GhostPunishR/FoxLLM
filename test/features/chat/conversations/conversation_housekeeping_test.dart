// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/features/chat/conversations/conversation_housekeeping.dart';
import 'package:foxllm/llm/model/chat_attachment.dart';
import 'package:foxllm/llm/model/chat_message.dart';

void main() {
  group('ce qui ne tient plus sous le plafond', () {
    test('rien à écarter tant que la limite n’est pas dépassée', () {
      expect(
        conversationsBeyondLimit(
          conversations: _conversations(3),
          activeConversationId: null,
          limit: 3,
        ),
        isEmpty,
      );
    });

    test('les plus anciennes partent en premier', () {
      // La liste va de la plus récente à la plus ancienne : ce sont donc les
      // dernières qui cèdent la place.
      final dropped = conversationsBeyondLimit(
        conversations: _conversations(6),
        activeConversationId: null,
        limit: 4,
      );

      expect(dropped.map((c) => c.id), <int>[5, 4]);
    });

    test('il n’en part jamais plus que nécessaire', () {
      final dropped = conversationsBeyondLimit(
        conversations: _conversations(10),
        activeConversationId: null,
        limit: 9,
      );

      expect(dropped, hasLength(1));
    });

    test('la conversation ouverte est épargnée, même la plus ancienne', () {
      // La voir disparaître sous ses yeux serait pire que de dépasser la
      // limite d'une unité.
      final dropped = conversationsBeyondLimit(
        conversations: _conversations(6),
        activeConversationId: 5,
        limit: 4,
      );

      expect(dropped.map((c) => c.id), isNot(contains(5)));
      expect(dropped.map((c) => c.id), <int>[4, 3]);
    });

    test('une seule conversation ouverte ne part jamais', () {
      final dropped = conversationsBeyondLimit(
        conversations: _conversations(1),
        activeConversationId: 0,
        limit: 0,
      );

      expect(dropped, isEmpty);
    });

    test('la liste rendue ne modifie pas celle qu’on lui donne', () {
      final conversations = _conversations(6);
      conversationsBeyondLimit(
        conversations: conversations,
        activeConversationId: null,
        limit: 4,
      );

      expect(conversations, hasLength(6));
    });
  });

  group('ce que plus personne ne cite', () {
    test('une copie qu’aucune liste ne mentionne est effaçable', () {
      final orphan = _attachment('orpheline.png');

      expect(
        unreferencedAttachments(
          candidates: <ChatAttachment>[orphan],
          conversations: const <ChatConversation>[],
          thread: const <ChatMessage>[],
          pending: const <ChatAttachment>[],
          queued: const <List<ChatAttachment>>[],
        ).map((a) => a.path),
        <String>['/tmp/orpheline.png'],
      );
    });

    test('une copie citée par l’historique est protégée', () {
      final shared = _attachment('partagee.png');

      expect(
        unreferencedAttachments(
          candidates: <ChatAttachment>[shared],
          conversations: <ChatConversation>[
            _conversation(1, <ChatAttachment>[_attachment('partagee.png')]),
          ],
          thread: const <ChatMessage>[],
          pending: const <ChatAttachment>[],
          queued: const <List<ChatAttachment>>[],
        ),
        isEmpty,
      );
    });

    test('une version conservée protège ses copies', () {
      // Le défaut d'origine : la suppression ne parcourait que le fil
      // visible, et laissait les copies d'une version conservée sur le disque.
      final kept = _attachment('conservee.png');
      final conversation = ChatConversation(
        id: 2,
        title: 'Deux versions',
        updatedAt: DateTime(2026, 9, 20),
        messages: const <ChatMessage>[],
        previousMessages: <ChatMessage>[
          ChatMessage(
            role: ChatRole.user,
            content: 'Avant',
            attachments: <ChatAttachment>[_attachment('conservee.png')],
          ),
        ],
      );

      expect(
        unreferencedAttachments(
          candidates: <ChatAttachment>[kept],
          conversations: <ChatConversation>[conversation],
          thread: const <ChatMessage>[],
          pending: const <ChatAttachment>[],
          queued: const <List<ChatAttachment>>[],
        ),
        isEmpty,
      );
    });

    test('le fil affiché, le brouillon et la file protègent aussi', () {
      for (final protector in <String>['fil', 'brouillon', 'file']) {
        final candidate = _attachment('$protector.png');
        final copy = _attachment('$protector.png');

        final removable = unreferencedAttachments(
          candidates: <ChatAttachment>[candidate],
          conversations: const <ChatConversation>[],
          thread: protector == 'fil'
              ? <ChatMessage>[
                  ChatMessage(
                    role: ChatRole.user,
                    content: 'Tiens',
                    attachments: <ChatAttachment>[copy],
                  ),
                ]
              : const <ChatMessage>[],
          pending: protector == 'brouillon'
              ? <ChatAttachment>[copy]
              : const <ChatAttachment>[],
          queued: protector == 'file'
              ? <List<ChatAttachment>>[
                  <ChatAttachment>[copy],
                ]
              : const <List<ChatAttachment>>[],
        );

        expect(removable, isEmpty, reason: '$protector ne protège pas');
      }
    });

    test('deux objets distincts pour un même fichier se reconnaissent', () {
      // Ce sont deux objets différents, avec le même chemin : la comparaison
      // doit porter sur le fichier, pas sur l'identité de l'objet.
      final candidate = ChatAttachment(
        name: 'photo.png',
        path: '/tmp/photo.png',
        mimeType: 'image/png',
        sizeBytes: 10,
      );
      final other = ChatAttachment(
        name: 'renommee.png',
        path: '/tmp/photo.png',
        mimeType: 'image/png',
        sizeBytes: 999,
      );

      expect(
        unreferencedAttachments(
          candidates: <ChatAttachment>[candidate],
          conversations: const <ChatConversation>[],
          thread: <ChatMessage>[
            ChatMessage(
              role: ChatRole.user,
              content: 'Tiens',
              attachments: <ChatAttachment>[other],
            ),
          ],
          pending: const <ChatAttachment>[],
          queued: const <List<ChatAttachment>>[],
        ),
        isEmpty,
      );
    });

    test('le tri des effaçables garde l’ordre reçu', () {
      final first = _attachment('a.png');
      final second = _attachment('b.png');

      expect(
        unreferencedAttachments(
          candidates: <ChatAttachment>[first, second],
          conversations: const <ChatConversation>[],
          thread: const <ChatMessage>[],
          pending: const <ChatAttachment>[],
          queued: const <List<ChatAttachment>>[],
        ).map((a) => a.path),
        <String>['/tmp/a.png', '/tmp/b.png'],
      );
    });
  });
}

List<ChatConversation> _conversations(int count) => <ChatConversation>[
  for (var index = 0; index < count; index++)
    ChatConversation(
      id: index,
      title: 'Conversation $index',
      updatedAt: DateTime(2026, 9, 20).subtract(Duration(days: index)),
      messages: const <ChatMessage>[],
    ),
];

ChatConversation _conversation(int id, List<ChatAttachment> attachments) =>
    ChatConversation(
      id: id,
      title: 'Avec pièces jointes',
      updatedAt: DateTime(2026, 9, 20),
      messages: <ChatMessage>[
        ChatMessage(
          role: ChatRole.user,
          content: 'Tiens',
          attachments: attachments,
        ),
      ],
    );

ChatAttachment _attachment(String name) => ChatAttachment(
  name: name,
  path: '/tmp/$name',
  mimeType: 'image/png',
  sizeBytes: 4,
);
