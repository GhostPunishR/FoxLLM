import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/local_backend_provider.dart';
import '../../core/llm/personal_api_chat_backend.dart';
import 'chat_screen.dart';

class ChatBackendHost extends ConsumerWidget {
  const ChatBackendHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localBackend = ref.read(localLlmBackendProvider);
    final personalBackend = ref.watch(personalApiChatBackendProvider);
    final activeBackend = personalBackend ?? localBackend;

    return ProviderScope(
      overrides: [localLlmBackendProvider.overrideWithValue(activeBackend)],
      child: const ChatScreen(),
    );
  }
}
