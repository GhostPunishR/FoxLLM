// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:foxllm/features/chat/conversations/chat_conversation.dart';

typedef ConversationDirectoryProvider = Future<Directory> Function();

/// Le fichier d'historique existe mais n'a pas pu être lu.
///
/// À distinguer d'un historique réellement vide : sur un échec de lecture, la
/// liste en mémoire ne dit rien de ce que contient le fichier.
class ConversationLoadException implements Exception {
  const ConversationLoadException(this.cause);

  final Object cause;

  @override
  String toString() => 'Historique illisible : $cause';
}

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
    } catch (error, stackTrace) {
      // Le fichier existe mais ne se lit pas : ce n'est pas un historique
      // vide, et le confondre avec un historique vide ferait écrire cette
      // liste vide par-dessus. L'appelant décide quoi en faire ; l'ouverture
      // du chat, elle, n'est pas empêchée.
      Error.throwWithStackTrace(ConversationLoadException(error), stackTrace);
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

  /// Rien ne part tant que l'historique n'a pas été relu.
  ///
  /// La liste en mémoire est vide au lancement. L'écrire à ce moment, sur un
  /// passage en arrière-plan ou un premier envoi, remplacerait le fichier par
  /// cette liste vide. Les demandes reçues pendant l'attente ne sont pas
  /// perdues : elles partent à la libération, avec l'état d'alors.
  bool _held = true;

  /// La relecture a échoué : la liste en mémoire ne dit rien de ce que
  /// contient le fichier, et l'écrire le détruirait.
  ///
  /// Distinct d'un historique réellement vide, qui lui peut être écrit.
  bool _abandoned = false;

  /// Une écriture est partie et n'est pas revenue.
  ///
  /// Tant qu'elle dure, les changements marquent l'état comme modifié sans
  /// prendre de nouvel instantané : un stockage lent accumulait sinon autant
  /// de copies de tout l'historique qu'il y avait eu de demandes.
  bool _writing = false;

  /// Une demande explicite attend, par opposition à un simple fragment.
  ///
  /// Distingue ce qui doit partir dès que possible (fin de génération, arrêt,
  /// navigation, renommage, suppression, fermeture) de ce qui peut attendre le
  /// prochain intervalle.
  bool _urgent = false;

  /// Vrai depuis le dernier échec non suivi d'une réussite.
  ///
  /// Sert à n'avertir qu'une fois : pendant une génération, une panne de
  /// disque ferait sinon apparaître le même message à chaque groupe de
  /// fragments.
  bool _failing = false;

  /// Nombre d'écritures réellement lancées, pour les tests.
  int writeCount = 0;

  /// Autorise les écritures : l'historique a été relu.
  void release() {
    if (_disposed || _abandoned) {
      return;
    }
    _held = false;
    _startIfIdle();
  }

  /// Interdit définitivement les écritures : l'historique n'a pas pu être lu.
  ///
  /// Mieux vaut ne plus rien enregistrer que remplacer un fichier existant par
  /// une liste vide qui ne vient que de l'échec de sa lecture.
  void abandon() {
    _abandoned = true;
    _held = true;
    _timer?.cancel();
    _timer = null;
  }

  /// Vrai tant qu'aucune écriture n'est permise.
  bool get isHeld => _held;

  /// Note un changement sans importance immédiate : l'écriture part au plus
  /// une fois par [interval].
  void schedule() {
    if (_disposed) {
      return;
    }
    _dirty = true;
    _timer ??= Timer(interval, _onTimer);
  }

  /// Demande une écriture dès que possible.
  ///
  /// À utiliser pour tout ce qui doit être conservé même si l'application
  /// s'arrête juste après : fin de génération, arrêt, erreur, navigation,
  /// renommage, suppression. L'appel vaut même sans planification en attente,
  /// sinon un changement ponctuel comme un renommage ne partirait jamais.
  ///
  /// Si une écriture est en cours, la demande n'est pas perdue : elle part
  /// dès son retour, avec l'état d'alors.
  void flush() {
    if (_disposed) {
      return;
    }
    _dirty = true;
    _urgent = true;
    _startIfIdle();
  }

  void _onTimer() {
    _timer = null;
    _startIfIdle();
  }

  void _startIfIdle() {
    _timer?.cancel();
    _timer = null;
    if (!_dirty || _writing || _held) {
      return;
    }
    unawaited(_write());
  }

  Future<void> _write() async {
    // L'instantané est pris ici, jamais à la demande : une écriture différée
    // porte donc l'état du moment où elle part, et ne peut pas réintroduire
    // une conversation supprimée entre-temps.
    _dirty = false;
    _urgent = false;
    _writing = true;
    writeCount++;
    try {
      await _save(_snapshot());
      _failing = false;
    } catch (error) {
      if (!_failing) {
        _failing = true;
        _onError?.call(error);
      }
    } finally {
      _writing = false;
      if (_dirty && !_held) {
        if (_urgent || _disposed) {
          // Une demande explicite, ou la dernière écriture après fermeture.
          unawaited(_write());
        } else {
          // Simples fragments : on garde la cadence au lieu d'enchaîner.
          _timer ??= Timer(interval, _onTimer);
        }
      }
    }
  }

  /// Écrit ce qui reste en attente, puis n'accepte plus de nouvelle demande.
  ///
  /// Une écriture déjà partie n'est pas interrompue, et ce qui a changé
  /// pendant celle-ci part encore : c'est la dernière chance de conserver les
  /// fragments reçus juste avant la fermeture de l'écran.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _urgent = true;
    _startIfIdle();
    _disposed = true;
  }
}

final conversationStoreProvider = Provider<ConversationStore>(
  (ref) => ConversationStore(),
);
