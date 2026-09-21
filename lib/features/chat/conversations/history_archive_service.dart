// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:typed_data';

import 'package:foxllm/features/chat/attachments/attachment_store.dart';
import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/features/chat/conversations/history_archive.dart';
import 'package:foxllm/llm/model/chat_attachment.dart';
import 'package:foxllm/llm/model/chat_message.dart';

/// Ce qu'un import a réellement rétabli.
class HistoryImportResult {
  const HistoryImportResult({
    required this.conversations,
    required this.restoredAttachments,
    required this.skippedConversations,
    required this.missingAttachments,
  });

  final List<ChatConversation> conversations;
  final int restoredAttachments;
  final int skippedConversations;

  /// Pièces jointes citées par une conversation mais absentes de l'archive.
  ///
  /// Comptées et dites : le message reste, mais sa pièce jointe ne rouvrira
  /// pas, et mieux vaut l'annoncer que laisser découvrir une vignette morte.
  final int missingAttachments;
}

/// Exporte et réimporte l'historique, pièces jointes comprises.
///
/// FoxLLM refuse la sauvegarde Android vers Google Drive, et l'assume dans sa
/// politique de confidentialité : en changeant de téléphone, tout est perdu.
/// Cet export est la contrepartie de cette promesse.
class HistoryArchiveService {
  const HistoryArchiveService({
    required AttachmentStore attachments,
    required String appVersion,
  }) : _attachments = attachments,
       _appVersion = appVersion;

  final AttachmentStore _attachments;
  final String _appVersion;

  /// Rassemble l'historique et ses pièces jointes en un seul fichier.
  Future<String> export(
    List<ChatConversation> conversations, {
    DateTime? exportedAt,
  }) async {
    final bytes = <String, Uint8List>{};
    for (final attachment in _allAttachments(conversations)) {
      if (bytes.containsKey(attachment.path)) {
        continue;
      }
      // Une pièce jointe déjà disparue de l'appareil ne fait pas échouer
      // l'export : le reste de l'historique vaut mieux que rien.
      final content = await _attachments.read(attachment);
      if (content != null) {
        bytes[attachment.path] = content;
      }
    }

    return encodeHistoryArchive(
      conversations: conversations,
      attachments: bytes,
      appVersion: _appVersion,
      exportedAt: exportedAt ?? DateTime.now(),
    );
  }

  /// Relit une archive et réécrit ses pièces jointes dans l'espace privé.
  ///
  /// Les chemins de l'archive désignent l'appareil d'origine : ils ne veulent
  /// rien dire ici. Chaque fichier est donc recopié, et les messages sont
  /// réécrits pour désigner la nouvelle copie.
  Future<HistoryImportResult> import(String contents) async {
    final archive = decodeHistoryArchive(contents);

    final remapped = <String, ChatAttachment>{};
    var restored = 0;
    for (final entry in archive.attachments.entries) {
      final source = _findAttachment(archive.conversations, entry.key);
      if (source == null) {
        continue;
      }
      final saved = await _attachments.save(
        name: source.name,
        mimeType: source.mimeType,
        bytes: entry.value,
      );
      remapped[entry.key] = saved;
      restored++;
    }

    var missing = 0;
    final rebuilt = <ChatConversation>[];
    for (final conversation in archive.conversations) {
      rebuilt.add(
        ChatConversation(
          id: conversation.id,
          title: conversation.title,
          updatedAt: conversation.updatedAt,
          messages: _remapMessages(
            conversation.messages,
            remapped,
            () => missing++,
          ),
          previousMessages: conversation.previousMessages == null
              ? null
              : _remapMessages(
                  conversation.previousMessages!,
                  remapped,
                  () => missing++,
                ),
        ),
      );
    }

    return HistoryImportResult(
      conversations: rebuilt,
      restoredAttachments: restored,
      skippedConversations: archive.skippedConversations,
      missingAttachments: missing,
    );
  }

  List<ChatMessage> _remapMessages(
    List<ChatMessage> messages,
    Map<String, ChatAttachment> remapped,
    void Function() onMissing,
  ) => messages
      .map((message) {
        if (message.attachments.isEmpty) {
          return message;
        }
        final attachments = <ChatAttachment>[];
        for (final attachment in message.attachments) {
          final replacement = remapped[attachment.path];
          if (replacement == null) {
            onMissing();
            continue;
          }
          attachments.add(replacement);
        }
        return message.copyWith(attachments: attachments);
      })
      .toList(growable: false);

  Iterable<ChatAttachment> _allAttachments(
    List<ChatConversation> conversations,
  ) sync* {
    for (final conversation in conversations) {
      for (final message in conversation.messages) {
        yield* message.attachments;
      }
      for (final message
          in conversation.previousMessages ?? const <ChatMessage>[]) {
        yield* message.attachments;
      }
    }
  }

  ChatAttachment? _findAttachment(
    List<ChatConversation> conversations,
    String path,
  ) {
    for (final attachment in _allAttachments(conversations)) {
      if (attachment.path == path) {
        return attachment;
      }
    }
    return null;
  }
}
