// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:foxllm/features/chat/attachments/attachment_store.dart';
import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/features/chat/conversations/history_archive_service.dart';
import 'package:foxllm/llm/model/chat_attachment.dart';
import 'package:foxllm/llm/model/chat_message.dart';

/// L'aller-retour complet : export d'un appareil, import sur un autre.
///
/// Les chemins d'une archive désignent l'appareil d'origine et ne veulent rien
/// dire ailleurs. C'est le cœur du problème qu'un export doit résoudre, et ce
/// que ces contrôles vérifient.
void main() {
  late Directory source;
  late Directory target;
  late AttachmentStore sourceStore;
  late AttachmentStore targetStore;

  setUp(() async {
    source = await Directory.systemTemp.createTemp('foxllm-export-');
    target = await Directory.systemTemp.createTemp('foxllm-import-');
    sourceStore = AttachmentStore(root: source);
    targetStore = AttachmentStore(root: target);
  });
  tearDown(() async {
    for (final directory in <Directory>[source, target]) {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    }
  });

  HistoryArchiveService serviceFor(AttachmentStore store) =>
      HistoryArchiveService(attachments: store, appVersion: '0.1.6');

  ChatConversation conversationWith(List<ChatAttachment> attachments) =>
      ChatConversation(
        id: 1,
        title: 'Avec une photo',
        updatedAt: DateTime.utc(2026, 9, 20),
        messages: <ChatMessage>[
          ChatMessage(
            role: ChatRole.user,
            content: 'Regarde',
            attachments: attachments,
          ),
          const ChatMessage(role: ChatRole.assistant, content: 'Je vois'),
        ],
      );

  test('une pièce jointe survit au passage d’un appareil à l’autre', () async {
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
    final saved = await sourceStore.save(
      name: 'photo.png',
      mimeType: 'image/png',
      bytes: bytes,
    );

    final archive = await serviceFor(sourceStore).export(<ChatConversation>[
      conversationWith(<ChatAttachment>[saved]),
    ]);

    // L'appareil d'origine disparaît : c'est le cas réel d'un changement de
    // téléphone, et la raison d'être de tout ceci.
    await source.delete(recursive: true);

    final result = await serviceFor(targetStore).import(archive);

    expect(result.restoredAttachments, 1);
    expect(result.missingAttachments, 0);

    final restored =
        result.conversations.single.messages.first.attachments.single;
    expect(restored.name, 'photo.png');
    expect(restored.mimeType, 'image/png');
    // Le chemin a changé : il désigne l'espace privé de la nouvelle
    // installation, pas celui de l'ancienne.
    expect(restored.path, isNot(saved.path));
    expect(restored.path, startsWith(target.path));
    expect(await File(restored.path).readAsBytes(), bytes);
  });

  test('une pièce jointe déjà disparue ne fait pas échouer l’export', () async {
    // L'utilisateur a pu effacer le fichier ailleurs : le reste de
    // l'historique vaut mieux que rien du tout.
    const ghost = ChatAttachment(
      name: 'perdue.png',
      path: '/nulle/part/perdue.png',
      mimeType: 'image/png',
      sizeBytes: 10,
    );

    final archive = await serviceFor(sourceStore).export(<ChatConversation>[
      conversationWith(<ChatAttachment>[ghost]),
    ]);
    final result = await serviceFor(targetStore).import(archive);

    expect(result.conversations, hasLength(1));
    expect(result.restoredAttachments, 0);
    // Le message reste, mais sa pièce jointe est comptée comme perdue plutôt
    // que laissée comme une vignette morte.
    expect(result.missingAttachments, 1);
    expect(result.conversations.single.messages.first.attachments, isEmpty);
  });

  test('une conversation sans pièce jointe passe inchangée', () async {
    final archive = await serviceFor(
      sourceStore,
    ).export(<ChatConversation>[conversationWith(const <ChatAttachment>[])]);
    final result = await serviceFor(targetStore).import(archive);

    expect(result.conversations.single.title, 'Avec une photo');
    expect(result.conversations.single.messages, hasLength(2));
    expect(result.restoredAttachments, 0);
    expect(result.missingAttachments, 0);
  });

  test(
    'deux messages qui citent le même fichier ne le copient qu’une fois',
    () async {
      final saved = await sourceStore.save(
        name: 'doc.txt',
        mimeType: 'text/plain',
        bytes: Uint8List.fromList(<int>[9, 9]),
      );
      final twice = ChatConversation(
        id: 2,
        title: 'Deux fois',
        updatedAt: DateTime.utc(2026, 9, 20),
        messages: <ChatMessage>[
          ChatMessage(
            role: ChatRole.user,
            content: 'un',
            attachments: <ChatAttachment>[saved],
          ),
          ChatMessage(
            role: ChatRole.user,
            content: 'deux',
            attachments: <ChatAttachment>[saved],
          ),
        ],
      );

      final archive = await serviceFor(
        sourceStore,
      ).export(<ChatConversation>[twice]);
      final result = await serviceFor(targetStore).import(archive);

      expect(result.restoredAttachments, 1);
      final paths = result.conversations.single.messages
          .expand((message) => message.attachments)
          .map((attachment) => attachment.path)
          .toSet();
      expect(paths, hasLength(1));
    },
  );
}
