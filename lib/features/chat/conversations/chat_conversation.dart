// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:foxllm/llm/model/chat_attachment.dart';
import 'package:foxllm/llm/model/citation.dart';
import 'package:foxllm/llm/model/chat_message.dart';

/// Conversation affichée dans le menu latéral et rechargeable après fermeture.
class ChatConversation {
  ChatConversation({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
  });

  final int id;
  String title;
  DateTime updatedAt;
  List<ChatMessage> messages;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages
        .map(
          (message) => <String, Object?>{
            'role': message.role.name,
            'content': message.content,
            // Seules les références sont enregistrées : les octets d'une
            // image feraient grossir ce fichier à chaque message.
            if (message.attachments.isNotEmpty)
              'attachments': message.attachments
                  .map((attachment) => attachment.toJson())
                  .toList(growable: false),
            if (message.citations.isNotEmpty)
              'citations': message.citations
                  .map((citation) => citation.toJson())
                  .toList(growable: false),
            if (message.rating != MessageRating.none)
              'rating': message.rating.name,
            // Absent quand la réponse est allée au bout : les historiques
            // écrits avant cette notion se relisent inchangés.
            if (message.outcome != GenerationOutcome.complete)
              'outcome': message.outcome.name,
            if (message.outcomeReason != null)
              'outcomeReason': message.outcomeReason,
          },
        )
        .toList(growable: false),
  };

  /// Reconstruit une conversation, ou `null` si l'entrée est inexploitable.
  ///
  /// Un fichier tronqué ou écrit par une version plus récente ne doit pas
  /// empêcher le reste de l'historique de se charger.
  static ChatConversation? fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      return null;
    }

    final id = value['id'];
    final title = value['title'];
    final updatedAt = DateTime.tryParse(value['updatedAt']?.toString() ?? '');
    if (id is! int || title is! String || updatedAt == null) {
      return null;
    }

    final rawMessages = value['messages'];
    if (rawMessages is! List) {
      return null;
    }

    final messages = <ChatMessage>[];
    for (final rawMessage in rawMessages) {
      if (rawMessage is! Map<Object?, Object?>) {
        continue;
      }
      final content = rawMessage['content'];
      if (content is! String) {
        continue;
      }

      final role = ChatRole.values.where(
        (role) => role.name == rawMessage['role'],
      );
      if (role.isEmpty) {
        continue;
      }
      final rawAttachments = rawMessage['attachments'];
      final attachments = <ChatAttachment>[];
      if (rawAttachments is List) {
        for (final rawAttachment in rawAttachments) {
          final attachment = ChatAttachment.fromJson(rawAttachment);
          if (attachment != null) {
            attachments.add(attachment);
          }
        }
      }

      final citations = <Citation>[];
      final rawCitations = rawMessage['citations'];
      if (rawCitations is List) {
        for (final rawCitation in rawCitations) {
          final citation = Citation.fromJson(rawCitation);
          if (citation != null) {
            citations.add(citation);
          }
        }
      }

      final rating = MessageRating.values.where(
        (value) => value.name == rawMessage['rating'],
      );

      // Un champ absent, ou écrit par une version qui connaît une issue de
      // plus, vaut « allée au bout » : mieux qu'un rejet de l'entrée.
      final outcome = GenerationOutcome.values.where(
        (value) => value.name == rawMessage['outcome'],
      );
      final outcomeReason = rawMessage['outcomeReason'];

      messages.add(
        ChatMessage(
          role: role.first,
          content: content,
          attachments: attachments,
          citations: citations,
          rating: rating.isEmpty ? MessageRating.none : rating.first,
          outcome: outcome.isEmpty ? GenerationOutcome.complete : outcome.first,
          outcomeReason: outcomeReason is String ? outcomeReason : null,
        ),
      );
    }

    if (messages.isEmpty) {
      return null;
    }

    return ChatConversation(
      id: id,
      title: title,
      updatedAt: updatedAt,
      messages: messages,
    );
  }
}
