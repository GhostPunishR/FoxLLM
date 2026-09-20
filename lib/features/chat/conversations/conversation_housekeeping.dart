// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

/// Les deux décisions d'entretien de l'historique : ce qui ne tient plus, et
/// ce que plus personne ne cite.
///
/// Sorties de l'écran de chat parce qu'elles ne dépendent de rien d'autre que
/// de leurs arguments. Une erreur y efface des fichiers qu'un message affiche
/// encore, ou perd une conversation sans le dire : ce sont des décisions à
/// vérifier une à une, ce qu'un écran de deux mille lignes ne permet pas.
library;

import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/llm/model/chat_attachment.dart';
import 'package:foxllm/llm/model/chat_message.dart';

/// Conversations à écarter pour tenir sous [limit], des plus anciennes aux
/// plus récentes.
///
/// La liste est rangée de la plus récente à la plus ancienne : ce sont donc
/// les dernières qui partent. La conversation ouverte est épargnée quelle que
/// soit sa place, parce que la voir disparaître sous ses yeux serait pire que
/// de dépasser la limite d'une unité.
///
/// Rend une liste vide quand rien n'est à écarter.
List<ChatConversation> conversationsBeyondLimit({
  required List<ChatConversation> conversations,
  required int? activeConversationId,
  required int limit,
}) {
  if (conversations.length <= limit) {
    return const <ChatConversation>[];
  }

  final dropped = <ChatConversation>[];
  for (var index = conversations.length - 1; index >= 0; index--) {
    if (conversations.length - dropped.length <= limit) {
      break;
    }
    final conversation = conversations[index];
    if (conversation.id == activeConversationId) {
      continue;
    }
    dropped.add(conversation);
  }
  return dropped;
}

/// Pièces jointes de [candidates] que plus rien ne cite.
///
/// Une même copie peut être citée à plusieurs endroits à la fois : par
/// l'historique, par le fil affiché, par une version conservée, par le
/// brouillon en cours ou par un message en attente. En effacer une encore
/// citée viderait la conversation où elle s'affiche.
///
/// La comparaison porte sur le chemin du fichier, et non sur l'objet : deux
/// messages qui décrivent la même copie sont deux objets distincts.
List<ChatAttachment> unreferencedAttachments({
  required Iterable<ChatAttachment> candidates,
  required Iterable<ChatConversation> conversations,
  required Iterable<ChatMessage> thread,
  required Iterable<ChatAttachment> pending,
  required Iterable<Iterable<ChatAttachment>> queued,
}) {
  final referenced = <String>{
    for (final conversation in conversations)
      for (final attachment in conversation.attachments) attachment.path,
    for (final message in thread)
      for (final attachment in message.attachments) attachment.path,
    for (final attachment in pending) attachment.path,
    for (final attachments in queued)
      for (final attachment in attachments) attachment.path,
  };

  return candidates
      .where((attachment) => !referenced.contains(attachment.path))
      .toList(growable: false);
}
