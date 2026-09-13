// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

// Fil de la conversation : accueil, bulles et pièces jointes envoyées.
// Partie de la bibliothèque `chat_screen.dart` : ces widgets ne servent
// qu'à cet écran et restent donc privés, sans changer de nom ni d'accès.

part of 'chat_screen.dart';

class _RestoringModelBanner extends StatelessWidget {
  const _RestoringModelBanner();

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: fox.accent),
          ),
          const SizedBox(width: 10),
          Text(
            'Chargement du modèle local…',
            style: TextStyle(color: fox.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _WelcomeState extends StatelessWidget {
  const _WelcomeState();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: EdgeInsets.only(top: constraints.maxHeight * 0.39),
          child: Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const FoxMark(size: 46),
                const SizedBox(height: 22),
                SizedBox(
                  width: 300,
                  child: Text(
                    "Salut ! Qu'aimeriez-vous\ndiscuter aujourd'hui ?",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.fox.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.28,
                      letterSpacing: -0.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.messages, required this.controller});

  final List<ChatMessage> messages;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final fox = context.fox;
        final message = messages[index];
        final isUser = message.role == ChatRole.user;
        if (message.role == ChatRole.system) {
          return const SizedBox.shrink();
        }

        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 720),
            margin: const EdgeInsets.only(bottom: 14),
            padding: isUser
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                : const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: isUser
                ? BoxDecoration(
                    color: fox.userBubble,
                    borderRadius: BorderRadius.circular(22),
                  )
                : null,
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (message.attachments.isNotEmpty) ...<Widget>[
                  for (final attachment in message.attachments) ...<Widget>[
                    _SentAttachment(attachment: attachment),
                    const SizedBox(height: 8),
                  ],
                ],
                if (message.content.isEmpty && message.attachments.isEmpty)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (message.content.isNotEmpty)
                  MessageMarkdown(
                    content: message.content,
                    textStyle: TextStyle(
                      color: fox.textPrimary,
                      fontSize: 16,
                      height: 1.45,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Pièce jointe telle qu'elle apparaît dans le fil, une fois envoyée.
///
/// Une image s'affiche en aperçu, un fichier en carte nommée : le contenu du
/// fichier part au modèle mais n'encombre pas la conversation.
class _SentAttachment extends StatelessWidget {
  const _SentAttachment({required this.attachment});

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;

    if (attachment.isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260, maxWidth: 260),
          child: Image.file(
            File(attachment.path),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _MissingAttachment(attachment: attachment),
          ),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: fox.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fox.border),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _AttachmentIcon(attachment: attachment, size: 34),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fox.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  formatAttachmentSize(attachment.sizeBytes),
                  style: TextStyle(color: fox.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pièce jointe dont la copie a disparu de l'appareil.
class _MissingAttachment extends StatelessWidget {
  const _MissingAttachment({required this.attachment});

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;
    return Container(
      padding: const EdgeInsets.all(12),
      color: fox.surfaceInput,
      child: Text(
        '« ${attachment.name} » n’est plus sur l’appareil.',
        style: TextStyle(color: fox.textSecondary, fontSize: 13),
      ),
    );
  }
}
