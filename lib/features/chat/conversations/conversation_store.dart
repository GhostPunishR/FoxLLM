// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:foxllm/features/chat/conversations/chat_conversation.dart';

typedef ConversationDirectoryProvider = Future<Directory> Function();

/// Enregistre l'historique des conversations dans le stockage privé de
/// l'application, sous forme d'un unique fichier JSON.
///
/// Le stockage sécurisé ne convient pas ici : il est conçu pour de courts
/// secrets, alors qu'un historique peut peser plusieurs centaines de kilo-octets.
class ConversationStore {
  ConversationStore({
    ConversationDirectoryProvider? applicationSupportDirectory,
  }) : _applicationSupportDirectory =
           applicationSupportDirectory ?? getApplicationSupportDirectory;

  /// Au-delà, les conversations les plus anciennes sont oubliées pour que le
  /// fichier ne grossisse pas indéfiniment.
  static const maxConversations = 100;

  static const _fileName = 'conversations.json';

  final ConversationDirectoryProvider _applicationSupportDirectory;

  /// Sérialisation en cours, pour ne jamais écrire deux fois en parallèle.
  Future<void> _pending = Future<void>.value();

  Future<File> _file() async {
    final directory = await _applicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }

  Future<List<ChatConversation>> load() async {
    final file = await _file();
    if (!await file.exists()) {
      return <ChatConversation>[];
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<Object?, Object?>) {
        return <ChatConversation>[];
      }
      final rawConversations = decoded['conversations'];
      if (rawConversations is! List) {
        return <ChatConversation>[];
      }

      final conversations = <ChatConversation>[];
      for (final raw in rawConversations) {
        final conversation = ChatConversation.fromJson(raw);
        if (conversation != null) {
          conversations.add(conversation);
        }
      }
      conversations.sort(
        (left, right) => right.updatedAt.compareTo(left.updatedAt),
      );
      return conversations;
    } catch (_) {
      // Historique illisible : on repart d'une liste vide plutôt que d'empêcher
      // l'ouverture du chat.
      return <ChatConversation>[];
    }
  }

  /// Enregistre l'historique, les écritures successives étant sérialisées.
  Future<void> save(List<ChatConversation> conversations) {
    final snapshot = conversations
        .take(maxConversations)
        .map((conversation) => conversation.toJson())
        .toList(growable: false);

    _pending = _pending.then((_) => _write(snapshot)).catchError((Object _) {});
    return _pending;
  }

  Future<void> _write(List<Map<String, Object?>> snapshot) async {
    final file = await _file();
    final partial = File('${file.path}.part');
    try {
      // Écriture puis renommage : une fermeture brutale en cours d'écriture ne
      // laisse pas un historique tronqué à la place de l'ancien.
      await partial.writeAsString(
        jsonEncode(<String, Object?>{'conversations': snapshot}),
        flush: true,
      );
      await partial.rename(file.path);
    } catch (_) {
      if (await partial.exists()) {
        await partial.delete();
      }
      rethrow;
    }
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) {
      await file.delete();
    }
  }
}

final conversationStoreProvider = Provider<ConversationStore>(
  (ref) => ConversationStore(),
);
