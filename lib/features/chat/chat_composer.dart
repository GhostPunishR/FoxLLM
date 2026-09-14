// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

// Zone de saisie : pièces jointes, modes, dictée et envoi.
// Partie de la bibliothèque `chat_screen.dart` : ces widgets ne servent
// qu'à cet écran et restent donc privés, sans changer de nom ni d'accès.

part of 'chat_screen.dart';

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.isGenerating,
    required this.modes,
    required this.attachments,
    required this.onRemoveAttachment,
    required this.onReflection,
    required this.onSearch,
    required this.onAdd,
    required this.isDictating,
    required this.onVoiceStart,
    required this.onVoiceEnd,
    required this.onVoiceTap,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool isGenerating;

  /// Réflexion et recherche web, pour montrer lesquels sont actifs.
  final ChatModes modes;

  /// Pièces jointes du brouillon, affichées au-dessus du champ.
  final List<ChatAttachment> attachments;
  final void Function(ChatAttachment attachment) onRemoveAttachment;

  final VoidCallback onReflection;
  final VoidCallback onSearch;
  final VoidCallback onAdd;

  /// Dictée en cours : le bouton du micro s'allume et le champ se remplit.
  final bool isDictating;
  final VoidCallback onVoiceStart;
  final VoidCallback onVoiceEnd;
  final VoidCallback onVoiceTap;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fox.surfaceInput,
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: fox.borderStrong),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 13, 12, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (attachments.isNotEmpty) ...<Widget>[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final attachment in attachments)
                        _AttachmentChip(
                          attachment: attachment,
                          onRemove: () => onRemoveAttachment(attachment),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  keyboardAppearance: Theme.of(context).brightness,
                  style: TextStyle(color: fox.textPrimary, fontSize: 17),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: isDictating
                        ? 'Parle, je t’écoute…'
                        : isGenerating
                        ? 'Mettre un message en attente…'
                        : 'Demander à FoxLLM',
                    hintStyle: TextStyle(
                      color: fox.textSecondary,
                      fontSize: 17,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              _ToolChip(
                                icon: Icons.psychology_alt_outlined,
                                label: 'Réflexion',
                                isActive: modes.reasoning,
                                onPressed: onReflection,
                              ),
                              const SizedBox(width: 8),
                              _ToolChip(
                                icon: Icons.language,
                                label: 'Rechercher',
                                isActive: modes.webSearch,
                                onPressed: onSearch,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    _RoundComposerButton(
                      tooltip: 'Ajouter',
                      icon: Icons.add,
                      onPressed: onAdd,
                    ),
                    const SizedBox(width: 3),
                    // Un seul bouton, qui prend le rôle du moment : dicter,
                    // envoyer, ou arrêter. Un troisième bouton apparaissant à
                    // la première frappe déplaçait les deux autres sous le
                    // doigt, juste avant qu'on les vise.
                    //
                    // Seul ce bouton observe le brouillon : le reste de
                    // l'écran, liste de messages comprise, n'est pas
                    // reconstruit à chaque frappe.
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (context, value, child) {
                        // La dictée garde son bouton jusqu'au relâchement : la
                        // parole remplit le champ, et laisser le brouillon
                        // changer le widget sous le doigt ferait disparaître
                        // celui qui attend le relâchement.
                        if (isDictating) {
                          return _DictationButton(
                            isDictating: true,
                            onStart: onVoiceStart,
                            onEnd: onVoiceEnd,
                            onTap: onVoiceTap,
                          );
                        }
                        // Une pièce jointe seule suffit à envoyer.
                        final hasDraft =
                            value.text.trim().isNotEmpty ||
                            attachments.isNotEmpty;

                        if (hasDraft) {
                          return _RoundComposerButton(
                            tooltip: isGenerating
                                ? 'Mettre en attente'
                                : 'Envoyer',
                            icon: Icons.arrow_upward_rounded,
                            filled: true,
                            onPressed: onSend,
                          );
                        }
                        if (isGenerating) {
                          return _RoundComposerButton(
                            tooltip: 'Arrêter',
                            icon: Icons.stop_rounded,
                            onPressed: onStop,
                          );
                        }
                        return _DictationButton(
                          isDictating: false,
                          onStart: onVoiceStart,
                          onEnd: onVoiceEnd,
                          onTap: onVoiceTap,
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Issue d'un envoi.
///
/// Distingue trois cas que l'appelant ne doit pas confondre : un refus avant
/// toute mutation, un message parti et abouti, et un message parti dont la
/// réponse a échoué. Seul le deuxième autorise la file à enchaîner.
enum _SendOutcome {
  /// Rien n'a été modifié : le message reste récupérable tel quel.
  refused,

  /// Le message a rejoint le fil et la réponse s'est terminée.
  sent,

  /// Le message a rejoint le fil, mais la réponse a échoué.
  failed,
}

/// Un envoi figé, avec tout ce qu'il lui faut pour aboutir.
///
/// Texte, pièces jointes et fil de destination voyagent ensemble. Le brouillon
/// du composeur n'est plus le véhicule des envois : la file et la régénération
/// s'en servaient comme d'un espace de travail, ce qui écrasait ce que
/// l'utilisateur était en train d'écrire ailleurs.
///
/// Figé avant la moindre attente : le chargement d'un modèle dure plusieurs
/// secondes, pendant lesquelles le brouillon et le fil affiché peuvent changer.
class _Outgoing {
  const _Outgoing({
    required this.text,
    required this.attachments,
    required this.conversationId,
    this.replaceFrom,
    this.fromComposer = false,
  });

  final String text;
  final List<ChatAttachment> attachments;

  /// Fil visé, ou `null` quand il reste à créer.
  ///
  /// Vérifié au moment de valider : un envoi préparé dans un fil ne doit pas
  /// atterrir dans celui qu'on a ouvert entre-temps.
  final int? conversationId;

  /// Indice à partir duquel la suite du fil est remplacée.
  ///
  /// Renseigné par une régénération ou une modification. La coupe n'a lieu
  /// qu'au moment de valider l'envoi : la faire avant tronquait la
  /// conversation même quand l'envoi était ensuite refusé.
  final int? replaceFrom;

  /// L'envoi vient du composeur, dont le texte est à vider une fois parti.
  final bool fromComposer;

  bool get isEmpty => text.isEmpty && attachments.isEmpty;
}

/// Pièce jointe du brouillon : aperçu, nom, taille et retrait.
class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.attachment, required this.onRemove});

  final ChatAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      decoration: BoxDecoration(
        color: fox.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fox.border),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _AttachmentThumbnail(attachment: attachment, size: 28),
          const SizedBox(width: 8),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  formatAttachmentSize(attachment.sizeBytes),
                  style: TextStyle(color: fox.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Retirer ${attachment.name}',
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(Icons.close_rounded, size: 16, color: fox.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Vignette d'une pièce jointe : l'image elle-même, ou une icône de fichier.
class _AttachmentThumbnail extends StatelessWidget {
  const _AttachmentThumbnail({required this.attachment, required this.size});

  final ChatAttachment attachment;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (attachment.isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(attachment.path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          // La copie a pu être effacée par le système : mieux vaut une icône
          // qu'une croix rouge au milieu du fil.
          errorBuilder: (context, error, stackTrace) =>
              _AttachmentIcon(attachment: attachment, size: size),
        ),
      );
    }
    return _AttachmentIcon(attachment: attachment, size: size);
  }
}

class _AttachmentIcon extends StatelessWidget {
  const _AttachmentIcon({required this.attachment, required this.size});

  final ChatAttachment attachment;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fox.surfaceInput,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        attachment.isImage
            ? Icons.image_outlined
            : Icons.insert_drive_file_outlined,
        size: size * 0.6,
        color: fox.textSecondary,
      ),
    );
  }
}

/// Mode du composer, dont l'aspect dit s'il est actif.
class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;
    // Actif : aplat orange plein. Inactif : simple contour, pour qu'un coup
    // d'œil suffise à savoir ce qui s'appliquera au prochain message.
    final background = isActive ? fox.accent : fox.accentSurface;
    final foreground = isActive ? fox.onAccent : fox.accentText;

    return Semantics(
      toggled: isActive,
      button: true,
      label: label,
      child: Tooltip(
        message: isActive ? '$label : activé' : '$label : désactivé',
        child: Material(
          color: background,
          shape: StadiumBorder(
            side: BorderSide(color: isActive ? fox.accent : fox.accentBorder),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Micro du composer : maintenu pour dicter, comme l'annonce le champ.
class _DictationButton extends StatelessWidget {
  const _DictationButton({
    required this.isDictating,
    required this.onStart,
    required this.onEnd,
    required this.onTap,
  });

  final bool isDictating;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  /// Appui simple : rappelle qu'il faut maintenir, plutôt que de ne rien faire.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;
    return Semantics(
      button: true,
      label: 'Dicter',
      hint: 'Maintenir pour dicter',
      child: Tooltip(
        message: isDictating ? 'Dictée en cours' : 'Maintenir pour dicter',
        child: GestureDetector(
          onTap: onTap,
          onLongPressStart: (_) => onStart(),
          onLongPressEnd: (_) => onEnd(),
          onLongPressCancel: onEnd,
          child: SizedBox.square(
            dimension: 42,
            child: Center(
              child: Container(
                width: 31,
                height: 31,
                decoration: BoxDecoration(
                  color: isDictating ? fox.accent : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDictating ? fox.accent : fox.textPrimary,
                    width: 1.7,
                  ),
                ),
                child: Icon(
                  isDictating ? Icons.mic_rounded : Icons.graphic_eq_rounded,
                  color: isDictating ? fox.onAccent : fox.textPrimary,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundComposerButton extends StatelessWidget {
  const _RoundComposerButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.filled = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 42,
        child: InkResponse(
          radius: 21,
          onTap: onPressed,
          child: Center(
            child: Container(
              width: 31,
              height: 31,
              decoration: BoxDecoration(
                color: filled ? fox.accent : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: filled ? fox.accent : fox.textPrimary,
                  width: 1.7,
                ),
              ),
              child: Icon(
                icon,
                color: filled ? fox.onAccent : fox.textPrimary,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
