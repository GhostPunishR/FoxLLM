// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/features/chat/conversations/history_archive.dart';
import 'package:foxllm/llm/model/chat_attachment.dart';
import 'package:foxllm/llm/model/chat_message.dart';

/// L'archive portable de l'historique.
///
/// FoxLLM refuse délibérément la sauvegarde Android vers Google Drive, et la
/// politique de confidentialité l'assume : en changeant de téléphone, tout est
/// perdu. Un export manuel est la contrepartie de cette promesse, et il
/// n'existait pas.
void main() {
  ChatConversation conversation({
    int id = 1,
    String title = 'Un échange',
    List<ChatAttachment> attachments = const <ChatAttachment>[],
  }) => ChatConversation(
    id: id,
    title: title,
    updatedAt: DateTime.utc(2026, 9, 20),
    messages: <ChatMessage>[
      ChatMessage(
        role: ChatRole.user,
        content: 'Bonjour',
        attachments: attachments,
      ),
      const ChatMessage(role: ChatRole.assistant, content: 'Salut'),
    ],
  );

  String encode({
    List<ChatConversation>? conversations,
    Map<String, Uint8List> attachments = const <String, Uint8List>{},
  }) => encodeHistoryArchive(
    conversations: conversations ?? <ChatConversation>[conversation()],
    attachments: attachments,
    appVersion: '0.1.6',
    exportedAt: DateTime.utc(2026, 9, 20, 12),
  );

  test('un aller-retour rend la conversation intacte', () {
    final archive = decodeHistoryArchive(encode());

    expect(archive.conversations, hasLength(1));
    expect(archive.conversations.single.title, 'Un échange');
    expect(archive.conversations.single.messages, hasLength(2));
    expect(archive.skippedConversations, 0);
  });

  test('les pièces jointes voyagent dans le fichier', () {
    // C'est tout l'intérêt : l'historique courant ne garde que des chemins
    // vers l'espace privé de l'application, qui ne veulent plus rien dire
    // une fois celle-ci désinstallée.
    final bytes = Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
    final archive = decodeHistoryArchive(
      encode(attachments: <String, Uint8List>{'/privé/photo.png': bytes}),
    );

    expect(archive.attachments['/privé/photo.png'], bytes);
  });

  test('l’en-tête dit d’où vient le fichier', () {
    final decoded = jsonDecode(encode()) as Map<String, Object?>;
    final header = decoded['foxllm']! as Map<String, Object?>;

    expect(header['archive'], historyArchiveVersion);
    expect(header['appVersion'], '0.1.6');
    expect(header['exportedAt'], '2026-09-20T12:00:00.000Z');
  });

  test('un fichier qui n’est pas du JSON est refusé', () {
    expect(
      () => decodeHistoryArchive('ceci n’est pas une archive'),
      throwsA(
        isA<HistoryArchiveException>().having(
          (e) => e.defect,
          'defect',
          HistoryArchiveDefect.unreadable,
        ),
      ),
    );
  });

  test('un JSON étranger est refusé', () {
    expect(
      () => decodeHistoryArchive('{"autre":"application"}'),
      throwsA(
        isA<HistoryArchiveException>().having(
          (e) => e.defect,
          'defect',
          HistoryArchiveDefect.notAnArchive,
        ),
      ),
    );
  });

  test('une archive d’une version plus récente est refusée, et nommée', () {
    final future = jsonEncode(<String, Object?>{
      'foxllm': <String, Object?>{'archive': historyArchiveVersion + 1},
      'conversations': <Object?>[],
    });

    expect(
      () => decodeHistoryArchive(future),
      throwsA(
        isA<HistoryArchiveException>()
            .having((e) => e.defect, 'defect', HistoryArchiveDefect.tooRecent)
            .having((e) => e.detail, 'detail', '${historyArchiveVersion + 1}'),
      ),
    );
  });

  test('une archive sans conversation lisible est refusée', () {
    final empty = jsonEncode(<String, Object?>{
      'foxllm': <String, Object?>{'archive': historyArchiveVersion},
      'conversations': <Object?>[],
    });

    expect(
      () => decodeHistoryArchive(empty),
      throwsA(
        isA<HistoryArchiveException>().having(
          (e) => e.defect,
          'defect',
          HistoryArchiveDefect.empty,
        ),
      ),
    );
  });

  test('une entrée abîmée se perd seule, et se compte', () {
    // Une archive est souvent la seule copie qui reste : elle doit rendre ce
    // qu'elle peut, et dire ce qu'elle n'a pas pu.
    final mixed = jsonEncode(<String, Object?>{
      'foxllm': <String, Object?>{'archive': historyArchiveVersion},
      'conversations': <Object?>[
        conversation(id: 1).toJson(),
        'ceci n’est pas une conversation',
        conversation(id: 2, title: 'Deuxième').toJson(),
      ],
    });

    final archive = decodeHistoryArchive(mixed);

    expect(archive.conversations, hasLength(2));
    expect(archive.skippedConversations, 1);
  });

  test('une pièce jointe illisible se perd seule', () {
    final broken = jsonEncode(<String, Object?>{
      'foxllm': <String, Object?>{'archive': historyArchiveVersion},
      'conversations': <Object?>[conversation().toJson()],
      'attachments': <String, Object?>{
        '/bon.png': base64Encode(<int>[1, 2, 3]),
        '/abîmé.png': 'ceci n’est pas du base64 !!',
      },
    });

    final archive = decodeHistoryArchive(broken);

    expect(archive.conversations, hasLength(1));
    expect(archive.attachments.keys, <String>['/bon.png']);
  });
}
