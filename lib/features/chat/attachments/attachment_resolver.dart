// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';

import 'package:foxllm/features/chat/attachments/attachment_store.dart';
import 'package:foxllm/l10n/app_localizations.dart';
import 'package:foxllm/llm/model/chat_attachment.dart';
import 'package:foxllm/llm/model/chat_message.dart';

/// Le moteur choisi ne sait pas lire une pièce jointe du message.
/// Les deux raisons pour lesquelles une pièce jointe ne peut pas partir.
enum UnsupportedAttachmentKind {
  /// Le moteur en place ne lit pas les images.
  noImageSupport,

  /// Le fichier n'est pas du texte lisible.
  notText,
}

class UnsupportedAttachmentException implements Exception {
  const UnsupportedAttachmentException(this.message, {this.kind, this.name});

  /// Le message en français, gardé pour la trace et comme dernier recours.
  final String message;

  /// Pourquoi la pièce jointe est refusée, pour le redire dans la langue
  /// de l'interface.
  final UnsupportedAttachmentKind? kind;

  final String? name;

  String describe(AppLocalizations l10n) {
    final reason = kind;
    final file = name;
    if (reason == null || file == null) {
      return message;
    }
    return switch (reason) {
      UnsupportedAttachmentKind.noImageSupport => l10n.attachmentNoImages(file),
      UnsupportedAttachmentKind.notText => l10n.attachmentNotText(file),
    };
  }

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
  AppLocalizations? l10n,
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
            kind: UnsupportedAttachmentKind.noImageSupport,
            name: attachment.name,
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
          kind: UnsupportedAttachmentKind.notText,
          name: attachment.name,
        );
      }
      if (buffer.isNotEmpty) {
        buffer.write('\n\n');
      }
      buffer
        // Ce préfixe part au modèle avec le contenu du fichier : il suit la
        // langue de l'interface, comme les consignes.
        ..write(
          '${l10n?.attachmentPrefix(attachment.name) ?? 'Fichier joint : ${attachment.name}'}\n```\n',
        )
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
