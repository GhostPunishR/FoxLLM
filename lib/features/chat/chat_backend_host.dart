// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/local_backend_provider.dart';
import '../../core/llm/local_llm_backend.dart';
import '../../core/llm/personal_api_chat_backend.dart';
import 'chat_screen.dart';

/// Backend utilisé par l'écran de chat : l'API personnelle si elle est active,
/// sinon le moteur local.
///
/// Un `ProviderScope` imbriqué posant un override conditionnel ne convenait
/// pas : Riverpod n'accepte pas qu'un override apparaisse ou disparaisse en
/// cours de route. Les réglages étant lus de façon asynchrone, aucun override
/// n'existait au premier rendu, et celui ajouté ensuite était ignoré — le chat
/// réclamait alors un GGUF malgré une API personnelle configurée.
///
/// Ce provider n'est lu que dans les actions de l'écran, jamais pendant son
/// `build` : le moteur local n'est donc toujours pas construit au lancement.
final chatBackendProvider = Provider<LocalLlmBackend>((ref) {
  return ref.watch(personalApiChatBackendProvider) ??
      ref.watch(localLlmBackendProvider);
});

class ChatBackendHost extends StatelessWidget {
  const ChatBackendHost({super.key});

  @override
  Widget build(BuildContext context) => const ChatScreen();
}
