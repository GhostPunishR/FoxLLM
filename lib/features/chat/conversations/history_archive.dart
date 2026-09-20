// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'dart:typed_data';

import 'package:foxllm/features/chat/conversations/chat_conversation.dart';

/// Version du format d'archive.
///
/// Écrite dans le fichier pour qu'une archive produite par une version
/// ultérieure soit refusée clairement, plutôt que relue de travers.
const historyArchiveVersion = 1;

/// Ce qu'une archive peut avoir d'inexploitable.
enum HistoryArchiveDefect {
  /// Le fichier n'est pas du JSON, ou pas un objet.
  unreadable,

  /// Ce JSON n'est pas une archive FoxLLM.
  notAnArchive,

  /// Archive écrite par une version plus récente.
  tooRecent,

  /// Archive lisible, mais sans une seule conversation récupérable.
  empty,
}

class HistoryArchiveException implements Exception {
  const HistoryArchiveException(this.defect, {this.detail});

  final HistoryArchiveDefect defect;
  final String? detail;

  @override
  String toString() => 'HistoryArchiveException(${defect.name}, $detail)';
}

/// Contenu d'une archive relue.
class HistoryArchive {
  const HistoryArchive({
    required this.conversations,
    required this.attachments,
    required this.skippedConversations,
  });

  final List<ChatConversation> conversations;

  /// Octets des pièces jointes, rangés sous leur chemin d'origine.
  final Map<String, Uint8List> attachments;

  /// Entrées écartées faute d'être relisables.
  ///
  /// Comptées plutôt que tues : une archive à moitié lue doit le dire, sinon
  /// l'utilisateur croit avoir tout récupéré.
  final int skippedConversations;
}

/// Écrit une archive portable de l'historique.
///
/// Les pièces jointes voyagent **dans** le fichier, en base64, alors que
/// l'historique courant ne garde que leurs chemins. C'est le prix d'un export
/// utilisable ailleurs : un fichier qui renvoie à l'espace privé d'une
/// application désinstallée ne sert à rien, et c'est précisément le cas qu'un
/// export doit couvrir.
String encodeHistoryArchive({
  required List<ChatConversation> conversations,
  required Map<String, Uint8List> attachments,
  required String appVersion,
  required DateTime exportedAt,
}) => jsonEncode(<String, Object?>{
  'foxllm': <String, Object?>{
    'archive': historyArchiveVersion,
    'appVersion': appVersion,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
  },
  'conversations': conversations
      .map((conversation) => conversation.toJson())
      .toList(growable: false),
  'attachments': <String, Object?>{
    for (final entry in attachments.entries)
      entry.key: base64Encode(entry.value),
  },
});

/// Relit une archive, ou lève en disant pourquoi elle est inexploitable.
HistoryArchive decodeHistoryArchive(String contents) {
  final Object? decoded;
  try {
    decoded = jsonDecode(contents);
  } catch (_) {
    throw const HistoryArchiveException(HistoryArchiveDefect.unreadable);
  }
  if (decoded is! Map<Object?, Object?>) {
    throw const HistoryArchiveException(HistoryArchiveDefect.unreadable);
  }

  final header = decoded['foxllm'];
  if (header is! Map<Object?, Object?>) {
    throw const HistoryArchiveException(HistoryArchiveDefect.notAnArchive);
  }
  final version = header['archive'];
  if (version is! int) {
    throw const HistoryArchiveException(HistoryArchiveDefect.notAnArchive);
  }
  if (version > historyArchiveVersion) {
    throw HistoryArchiveException(
      HistoryArchiveDefect.tooRecent,
      detail: '$version',
    );
  }

  final rawConversations = decoded['conversations'];
  if (rawConversations is! List) {
    throw const HistoryArchiveException(HistoryArchiveDefect.notAnArchive);
  }

  final conversations = <ChatConversation>[];
  var skipped = 0;
  for (final raw in rawConversations) {
    // Une entrée abîmée ne doit pas emporter l'archive entière : c'est
    // souvent la seule copie qui reste.
    final conversation = ChatConversation.fromJson(raw, onLoss: () {});
    if (conversation == null) {
      skipped++;
    } else {
      conversations.add(conversation);
    }
  }
  if (conversations.isEmpty) {
    throw const HistoryArchiveException(HistoryArchiveDefect.empty);
  }

  final attachments = <String, Uint8List>{};
  final rawAttachments = decoded['attachments'];
  if (rawAttachments is Map<Object?, Object?>) {
    for (final entry in rawAttachments.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || value is! String) {
        continue;
      }
      try {
        attachments[key] = base64Decode(value);
      } catch (_) {
        // Une pièce jointe illisible se perd seule : la conversation qui la
        // cite reste lisible, et le message aussi.
      }
    }
  }

  return HistoryArchive(
    conversations: conversations,
    attachments: attachments,
    skippedConversations: skipped,
  );
}
