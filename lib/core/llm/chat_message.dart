// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'dart:typed_data';

import 'chat_attachment.dart';

enum ChatRole { system, user, assistant }

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    this.attachments = const <ChatAttachment>[],
    this.images = const <InlineImage>[],
  });

  const ChatMessage.system(String content)
    : this(role: ChatRole.system, content: content);

  const ChatMessage.user(String content)
    : this(role: ChatRole.user, content: content);

  const ChatMessage.assistant(String content)
    : this(role: ChatRole.assistant, content: content);

  final ChatRole role;
  final String content;

  /// Pièces jointes affichées dans le fil et conservées avec la conversation.
  final List<ChatAttachment> attachments;

  /// Images prêtes à partir, chargées juste avant l'envoi.
  ///
  /// Séparées de [attachments] : les octets d'une image ne doivent jamais
  /// rejoindre l'historique enregistré, qui grossirait à chaque message.
  final List<InlineImage> images;

  ChatMessage copyWith({
    String? content,
    List<ChatAttachment>? attachments,
    List<InlineImage>? images,
  }) => ChatMessage(
    role: role,
    content: content ?? this.content,
    attachments: attachments ?? this.attachments,
    images: images ?? this.images,
  );

  Map<String, Object> toApiJson() {
    if (images.isEmpty) {
      return <String, Object>{'role': role.name, 'content': content};
    }
    // Format multimodal des API compatibles OpenAI : le texte et les images
    // deviennent des morceaux successifs d'un même message.
    return <String, Object>{
      'role': role.name,
      'content': <Map<String, Object>>[
        if (content.isNotEmpty)
          <String, Object>{'type': 'text', 'text': content},
        for (final image in images)
          <String, Object>{
            'type': 'image_url',
            'image_url': <String, String>{'url': image.dataUrl},
          },
      ],
    };
  }
}

/// Image portée par un message au moment de la requête.
class InlineImage {
  const InlineImage({required this.mimeType, required this.bytes});

  final String mimeType;
  final Uint8List bytes;

  String get base64Data => base64Encode(bytes);

  /// Adresse en ligne attendue par les API compatibles OpenAI.
  String get dataUrl => 'data:$mimeType;base64,$base64Data';
}
