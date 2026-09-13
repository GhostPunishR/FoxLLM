import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/local_backend_provider.dart';
import '../../core/llm/personal_api_chat_backend.dart';
import 'chat_screen.dart';

/// Choisit le backend du chat sans forcer la création du moteur local.
///
/// Lire `localLlmBackendProvider` ici démarrerait l'isolate worker et
/// chargerait `libfoxgpt_native.so` — donc `llama.cpp` — avant même le premier
/// frame, ce qui allongeait d'autant l'écran vide au lancement. Tant qu'aucune
/// API personnelle n'est active, aucun override n'est posé : `ChatScreen`
/// utilise alors le provider racine, construit à la première utilisation réelle
/// (envoi d'un message, ouverture des modèles locaux).
class ChatBackendHost extends ConsumerWidget {
  const ChatBackendHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personalBackend = ref.watch(personalApiChatBackendProvider);

    return ProviderScope(
      overrides: [
        if (personalBackend != null)
          localLlmBackendProvider.overrideWithValue(personalBackend),
      ],
      child: const ChatScreen(),
    );
  }
}
