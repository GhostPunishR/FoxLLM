import '../../core/llm/chat_message.dart';

/// Conversation affichée dans le menu latéral et rechargeable après fermeture.
class ChatConversation {
  ChatConversation({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
  });

  final int id;
  final String title;
  DateTime updatedAt;
  List<ChatMessage> messages;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages
        .map(
          (message) => <String, Object?>{
            'role': message.role.name,
            'content': message.content,
          },
        )
        .toList(growable: false),
  };

  /// Reconstruit une conversation, ou `null` si l'entrée est inexploitable.
  ///
  /// Un fichier tronqué ou écrit par une version plus récente ne doit pas
  /// empêcher le reste de l'historique de se charger.
  static ChatConversation? fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      return null;
    }

    final id = value['id'];
    final title = value['title'];
    final updatedAt = DateTime.tryParse(value['updatedAt']?.toString() ?? '');
    if (id is! int || title is! String || updatedAt == null) {
      return null;
    }

    final rawMessages = value['messages'];
    if (rawMessages is! List) {
      return null;
    }

    final messages = <ChatMessage>[];
    for (final rawMessage in rawMessages) {
      if (rawMessage is! Map<Object?, Object?>) {
        continue;
      }
      final content = rawMessage['content'];
      if (content is! String) {
        continue;
      }
      final role = ChatRole.values.where(
        (role) => role.name == rawMessage['role'],
      );
      if (role.isEmpty) {
        continue;
      }
      messages.add(ChatMessage(role: role.first, content: content));
    }

    if (messages.isEmpty) {
      return null;
    }

    return ChatConversation(
      id: id,
      title: title,
      updatedAt: updatedAt,
      messages: messages,
    );
  }
}
