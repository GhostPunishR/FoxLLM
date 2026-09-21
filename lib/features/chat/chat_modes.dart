// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Modes du composer : réflexion et recherche web.
class ChatModes {
  const ChatModes({this.reasoning = false, this.webSearch = false});

  /// Demande au modèle d'exposer son raisonnement avant de conclure.
  final bool reasoning;

  /// Autorise le modèle à consulter le web pendant sa réponse.
  final bool webSearch;

  ChatModes copyWith({bool? reasoning, bool? webSearch}) => ChatModes(
    reasoning: reasoning ?? this.reasoning,
    webSearch: webSearch ?? this.webSearch,
  );

  @override
  bool operator ==(Object other) =>
      other is ChatModes &&
      other.reasoning == reasoning &&
      other.webSearch == webSearch;

  @override
  int get hashCode => Object.hash(reasoning, webSearch);

  @override
  String toString() => 'ChatModes(réflexion: $reasoning, web: $webSearch)';
}

/// Marge de génération quand la réflexion est active.
///
/// Un raisonnement exposé tient rarement dans la limite ordinaire : sans cette
/// marge, la réponse serait coupée avant la conclusion.
const int reasoningMaxTokens = 1536;

/// Conserve les modes choisis entre deux lancements.
class ChatModesStore {
  ChatModesStore({FlutterSecureStorage? storage})
    : _storage = storage ?? FlutterSecureStorage();

  static const _reasoningKey = 'foxllm.chat.mode.reasoning';
  static const _webSearchKey = 'foxllm.chat.mode.web_search';

  final FlutterSecureStorage _storage;

  Future<ChatModes> load() async {
    final reasoning = await _storage.read(key: _reasoningKey);
    final webSearch = await _storage.read(key: _webSearchKey);
    return ChatModes(
      reasoning: reasoning == 'true',
      webSearch: webSearch == 'true',
    );
  }

  Future<void> save(ChatModes modes) async {
    await _storage.write(key: _reasoningKey, value: '${modes.reasoning}');
    await _storage.write(key: _webSearchKey, value: '${modes.webSearch}');
  }
}

final chatModesStoreProvider = Provider<ChatModesStore>(
  (ref) => ChatModesStore(),
);

final chatModesProvider = NotifierProvider<ChatModesController, ChatModes>(
  ChatModesController.new,
);

class ChatModesController extends Notifier<ChatModes> {
  late Future<void> _restored;

  /// Vrai dès que l'utilisateur a basculé un mode dans cette session.
  bool _touched = false;

  @override
  ChatModes build() {
    // Le chat s'affiche sans attendre le stockage ; les modes enregistrés
    // arrivent ensuite.
    _touched = false;
    _restored = _restore();
    return const ChatModes();
  }

  Future<void> _restore() async {
    try {
      final stored = await ref.read(chatModesStoreProvider).load();
      // Une lecture lente ne doit pas revenir par-dessus une bascule faite
      // entre-temps.
      if (!_touched && stored != state) {
        state = stored;
      }
    } catch (_) {
      // Préférence illisible : les deux modes restent inactifs.
    }
  }

  /// Modes une fois la lecture du stockage terminée.
  Future<ChatModes> resolved() async {
    await _restored;
    return state;
  }

  Future<void> toggleReasoning() =>
      _apply(state.copyWith(reasoning: !state.reasoning));

  Future<void> toggleWebSearch() =>
      _apply(state.copyWith(webSearch: !state.webSearch));

  Future<void> _apply(ChatModes modes) async {
    _touched = true;
    state = modes;
    try {
      await ref.read(chatModesStoreProvider).save(modes);
    } catch (_) {
      // Le choix s'applique quand même à la session en cours.
    }
  }
}
