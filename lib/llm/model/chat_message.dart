// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'dart:typed_data';

import 'package:foxllm/llm/model/chat_attachment.dart';
import 'package:foxllm/llm/model/citation.dart';

enum ChatRole { system, user, assistant }

/// Avis de l'utilisateur sur une réponse.
///
/// Purement local : FoxLLM n'a pas de serveur à qui l'envoyer. C'est un
/// repère personnel, conservé avec la conversation, pas un retour transmis
/// à qui que ce soit.
enum MessageRating { none, up, down }

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    this.attachments = const <ChatAttachment>[],
    this.images = const <InlineImage>[],
    this.citations = const <Citation>[],
    this.rating = MessageRating.none,
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

  /// Sources consultées par le modèle, quand il a cherché sur le web.
  final List<Citation> citations;

  /// Avis local de l'utilisateur, conservé avec la conversation.
  final MessageRating rating;

  ChatMessage copyWith({
    String? content,
    List<ChatAttachment>? attachments,
    List<InlineImage>? images,
    List<Citation>? citations,
    MessageRating? rating,
  }) => ChatMessage(
    role: role,
    content: content ?? this.content,
    attachments: attachments ?? this.attachments,
    images: images ?? this.images,
    citations: citations ?? this.citations,
    rating: rating ?? this.rating,
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
