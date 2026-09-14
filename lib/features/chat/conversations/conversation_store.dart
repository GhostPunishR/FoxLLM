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
  ///
  /// La future rendue porte le sort de cette écriture précise : un disque
  /// plein ou un dossier devenu illisible remonte à l'appelant, au lieu de
  /// laisser croire que les messages sont conservés. La file, elle, survit à
  /// l'échec et traite les enregistrements suivants.
  Future<void> save(List<ChatConversation> conversations) {
    final snapshot = conversations
        .take(maxConversations)
        .map((conversation) => conversation.toJson())
        .toList(growable: false);

    final result = Completer<void>();
    _pending = _pending
        .then((_) => _write(snapshot))
        .then(
          (_) => result.complete(),
          // L'erreur part vers l'appelant ; la chaîne, elle, repart saine.
          onError: (Object error, StackTrace stackTrace) =>
              result.completeError(error, stackTrace),
        );
    return result.future;
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

/// Regroupe les enregistrements de l'historique.
///
/// Chaque fragment reçu pendant une génération modifie la conversation
/// active. Enregistrer à chacun revenait à réencoder tout l'historique et à
/// réécrire le fichier des dizaines de fois par seconde, pour un état
/// intermédiaire que personne ne relira.
///
/// L'état n'est pas figé à la planification mais relu au moment d'écrire :
/// une écriture différée ne peut donc pas ressusciter une conversation
/// supprimée entre-temps.
class ConversationPersister {
  ConversationPersister({
    required Future<void> Function(List<ChatConversation>) save,
    required List<ChatConversation> Function() snapshot,
    this.interval = const Duration(seconds: 2),
    void Function(Object error)? onError,
  }) : _save = save,
       _snapshot = snapshot,
       _onError = onError;

  final Future<void> Function(List<ChatConversation>) _save;
  final List<ChatConversation> Function() _snapshot;
  final void Function(Object error)? _onError;

  /// Écart minimal entre deux écritures différées.
  final Duration interval;

  Timer? _timer;
  bool _dirty = false;
  bool _disposed = false;

  /// Vrai depuis le dernier échec non suivi d'une réussite.
  ///
  /// Sert à n'avertir qu'une fois : pendant une génération, une panne de
  /// disque ferait sinon apparaître le même message à chaque groupe de
  /// fragments.
  bool _failing = false;

  /// Nombre d'écritures réellement lancées, pour les tests.
  int writeCount = 0;

  /// Note un changement sans importance immédiate : l'écriture part au plus
  /// une fois par [interval].
  void schedule() {
    if (_disposed) {
      return;
    }
    _dirty = true;
    _timer ??= Timer(interval, _writeIfNeeded);
  }

  /// Écrit l'état courant sans attendre.
  ///
  /// À utiliser pour tout ce qui doit être conservé même si l'application
  /// s'arrête juste après : fin de génération, arrêt, erreur, navigation,
  /// renommage, suppression. L'appel écrit même sans planification en
  /// attente, sinon un changement ponctuel comme un renommage ne partirait
  /// jamais.
  void flush() {
    _dirty = true;
    _writeIfNeeded();
  }

  void _writeIfNeeded() {
    _timer?.cancel();
    _timer = null;
    if (!_dirty || _disposed) {
      return;
    }
    _dirty = false;
    writeCount++;
    unawaited(
      _save(_snapshot()).then(
        (_) => _failing = false,
        onError: (Object error) {
          if (_failing) {
            return;
          }
          _failing = true;
          _onError?.call(error);
        },
      ),
    );
  }

  /// Écrit ce qui reste en attente, puis n'accepte plus rien.
  void dispose() {
    _writeIfNeeded();
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}

final conversationStoreProvider = Provider<ConversationStore>(
  (ref) => ConversationStore(),
);
