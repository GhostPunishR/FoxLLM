// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

enum ChatRole { system, user, assistant }

class ChatMessage {
  const ChatMessage({required this.role, required this.content});

  const ChatMessage.system(String content)
    : this(role: ChatRole.system, content: content);

  const ChatMessage.user(String content)
    : this(role: ChatRole.user, content: content);

  const ChatMessage.assistant(String content)
    : this(role: ChatRole.assistant, content: content);

  final ChatRole role;
  final String content;

  Map<String, Object> toApiJson() => <String, Object>{
    'role': role.name,
    'content': content,
  };
}
