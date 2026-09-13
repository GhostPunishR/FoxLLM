// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';

import '../../core/llm/chat_attachment.dart';
import '../../core/llm/chat_message.dart';
import 'attachment_store.dart';

/// Le moteur choisi ne sait pas lire une pièce jointe du message.
class UnsupportedAttachmentException implements Exception {
  const UnsupportedAttachmentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Prépare les messages à envoyer : le fil affiche des pièces jointes, la
/// requête a besoin de leur contenu.
///
/// Le texte d'un fichier rejoint le message, annoncé par son nom ; les images
/// deviennent des morceaux d'image. Rien de tout cela ne touche l'historique
/// enregistré, qui garde de simples références.
Future<List<ChatMessage>> resolveAttachments(
  List<ChatMessage> messages, {
  required AttachmentStore store,
  required bool supportsImages,
}) async {
  final resolved = <ChatMessage>[];

  for (final message in messages) {
    if (message.attachments.isEmpty) {
      resolved.add(message);
      continue;
    }

    final buffer = StringBuffer(message.content);
    final images = <InlineImage>[];

    for (final attachment in message.attachments) {
      final bytes = await store.read(attachment);
      if (bytes == null) {
        // La copie a disparu : le message part sans elle plutôt que d'échouer.
        continue;
      }

      if (attachment.isImage) {
        if (!supportsImages) {
          throw UnsupportedAttachmentException(
            'Le moteur choisi ne lit pas les images. Configure une API '
            'personnelle avec un modèle multimodal pour envoyer « '
            '${attachment.name} ».',
          );
        }
        images.add(InlineImage(mimeType: attachment.mimeType, bytes: bytes));
        continue;
      }

      final String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        throw UnsupportedAttachmentException(
          '« ${attachment.name} » n’est pas un fichier texte : aucun moteur '
          'ne sait le lire aujourd’hui.',
        );
      }
      if (buffer.isNotEmpty) {
        buffer.write('\n\n');
      }
      buffer
        ..write('Fichier joint : ${attachment.name}\n```\n')
        ..write(text.trimRight())
        ..write('\n```');
    }

    resolved.add(
      message.copyWith(
        content: buffer.toString(),
        // Les références ne servent plus : la requête porte le contenu.
        attachments: const <ChatAttachment>[],
        images: images,
      ),
    );
  }

  return resolved;
}
