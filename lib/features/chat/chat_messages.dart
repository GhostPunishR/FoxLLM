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
        // Le bloc descend au tiers de l'écran quand la place le permet.
        // Agrandi, le même texte prend plusieurs lignes de plus : l'espace
        // au-dessus lui cède du terrain, au lieu de le pousser dehors.
        final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
        final top = constraints.maxHeight * 0.39 / scale;

        return SingleChildScrollView(
          // Et si cela ne suffit pas, à très gros caractères sur un écran
          // court, le bloc défile plutôt que d'afficher la bande rayée de
          // débordement par-dessus l'accueil.
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: EdgeInsets.only(top: top),
              child: Align(
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const FoxMark(size: 46),
                    const SizedBox(height: 22),
                    SizedBox(
                      // La largeur suit l'écran quand il est plus étroit que
                      // la mesure choisie : une valeur fixe y déborderait.
                      //
                      // Bornée à zéro, et ce n'est pas une précaution de
                      // principe : la première image d'un lancement arrive
                      // avant les vraies dimensions de la fenêtre, donc avec
                      // une largeur nulle. La soustraction donnait alors une
                      // largeur négative, qu'un `SizedBox` refuse, et toute
                      // l'application tombait au démarrage.
                      width: (constraints.maxWidth - 32).clamp(0.0, 300.0),
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
            ),
          ),
        );
      },
    );
  }
}

/// Ce que l'écran sait faire d'un message, réuni pour ne pas traîner sept
/// rappels séparés jusqu'au fond de la liste.
class _MessageActions {
  const _MessageActions({
    required this.onCopy,
    required this.onRate,
    required this.onSpeak,
    required this.onShare,
    required this.onRegenerate,
    required this.onShowSources,
    required this.onEdit,
    required this.onCancelEdit,
    required this.onSubmitEdit,
  });

  final void Function(ChatMessage message) onCopy;
  final void Function(int index, MessageRating rating) onRate;
  final void Function(ChatMessage message) onSpeak;
  final void Function(ChatMessage message) onShare;
  final void Function(int index) onRegenerate;
  final void Function(ChatMessage message) onShowSources;
  final void Function(int index) onEdit;
  final VoidCallback onCancelEdit;
  final VoidCallback onSubmitEdit;
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.controller,
    required this.actions,
    required this.isGenerating,
    required this.speakingText,
    required this.editingIndex,
    required this.editController,
  });

  final List<ChatMessage> messages;
  final ScrollController controller;
  final _MessageActions actions;

  /// Une réponse encore en cours n'a pas de barre d'actions : rien n'est
  /// complet à copier, à lire ou à partager.
  final bool isGenerating;

  final String? speakingText;
  final int? editingIndex;
  final TextEditingController editController;

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

        if (isUser && editingIndex == index) {
          return _MessageEditor(
            controller: editController,
            onCancel: actions.onCancelEdit,
            onSubmit: actions.onSubmitEdit,
          );
        }

        final isLast = index == messages.length - 1;
        final showActions =
            !isUser && message.content.isNotEmpty && !(isGenerating && isLast);

        final bubble = Container(
          constraints: const BoxConstraints(maxWidth: 720),
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
              if (message.content.isEmpty &&
                  message.attachments.isEmpty &&
                  message.outcome == GenerationOutcome.complete)
                // Rien reçu et rien d'annoncé : la réponse est en route.
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
        );

        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 720),
            margin: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (isUser)
                  GestureDetector(
                    onLongPress: () => _showUserMenu(context, index, message),
                    child: bubble,
                  )
                else
                  bubble,
                if (!isUser && message.outcome != GenerationOutcome.complete)
                  _OutcomeNote(message: message),
                if (!isUser &&
                    (message.generationSpeed != null ||
                        message.contextFill != null))
                  _SpeedNote(
                    speed: message.generationSpeed,
                    contextFill: message.contextFill,
                  ),
                if (showActions)
                  _AssistantActions(
                    message: message,
                    index: index,
                    actions: actions,
                    isSpeaking:
                        speakingText != null &&
                        speakingText == message.content.trim(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Menu d'un message envoyé : appui long, sans horodatage.
  void _showUserMenu(BuildContext context, int index, ChatMessage message) {
    final fox = context.fox;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: fox.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: Icon(Icons.copy_rounded, color: fox.textSecondary),
              title: Text('Copier', style: TextStyle(color: fox.textPrimary)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                actions.onCopy(message);
              },
            ),
            ListTile(
              leading: Icon(Icons.notes_rounded, color: fox.textSecondary),
              title: Text(
                'Sélectionner le texte',
                style: TextStyle(color: fox.textPrimary),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showSelectableText(context, message.content);
              },
            ),
            ListTile(
              leading: Icon(Icons.edit_outlined, color: fox.textSecondary),
              title: Text(
                'Modifier le message',
                style: TextStyle(color: fox.textPrimary),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                actions.onEdit(index);
              },
            ),
            ListTile(
              leading: Icon(Icons.ios_share_rounded, color: fox.textSecondary),
              title: Text('Partager', style: TextStyle(color: fox.textPrimary)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                actions.onShare(message);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Bulle remplacée par un champ pendant la modification.
///
/// L'édition se fait sur place, à la ligne du message : c'est là que
/// l'utilisateur regarde, et le composer garde son propre brouillon intact.
class _MessageEditor extends StatelessWidget {
  const _MessageEditor({
    required this.controller,
    required this.onCancel,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: fox.surfaceInput,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: fox.accentBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: null,
            style: TextStyle(color: fox.textPrimary, fontSize: 16),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton(
                onPressed: onCancel,
                child: Text(
                  'Annuler',
                  style: TextStyle(color: fox.textSecondary),
                ),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: onSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: fox.accent,
                  foregroundColor: fox.onAccent,
                ),
                child: const Text('Envoyer'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Vitesse d'écriture d'une réponse produite sur l'appareil.
///
/// Discrète à dessein : c'est une information de mise au point, utile pour
/// comparer deux modèles ou juger d'un réglage, pas une décoration. Elle
/// n'apparaît que pour le moteur local, seul à la mesurer.
/// Ce que la dernière réponse locale a coûté : sa vitesse, et la place
/// qu'elle laisse.
///
/// Le remplissage répond à une question qu'on ne se posait qu'en butant
/// dessus : jusqu'ici, rien n'annonçait que la conversation approchait de la
/// fenêtre du modèle, et le refus arrivait sans prévenir.
class _SpeedNote extends StatelessWidget {
  const _SpeedNote({this.speed, this.contextFill});

  final double? speed;
  final double? contextFill;

  /// Au-delà, la note le dit en toutes lettres plutôt qu'en pourcentage seul.
  static const _warningThreshold = 0.85;

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;
    final l10n = AppLocalizations.of(context);
    final parts = <String>[];

    final rate = speed;
    if (rate != null) {
      // Une décimale en dessous de dix, aucune au-dessus : à trente jetons par
      // seconde, le dixième ne veut plus rien dire.
      parts.add(
        l10n.generationSpeed(
          rate < 10
              ? rate.toStringAsFixed(1).replaceAll('.', ',')
              : rate.round().toString(),
        ),
      );
    }

    final fill = contextFill;
    if (fill != null) {
      final percent = (fill * 100).round().toString();
      parts.add(
        fill >= _warningThreshold
            ? l10n.contextNearlyFull(percent)
            : l10n.contextFill(percent),
      );
    }

    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 2),
      child: Text(
        parts.join(' \u00b7 '),
        style: TextStyle(
          color: fill != null && fill >= _warningThreshold
              ? fox.accent
              : fox.textTertiary,
          fontSize: 11,
        ),
      ),
    );
  }
}

/// Barre sous une réponse terminée.
class _AssistantActions extends StatelessWidget {
  const _AssistantActions({
    required this.message,
    required this.index,
    required this.actions,
    required this.isSpeaking,
  });

  final ChatMessage message;
  final int index;
  final _MessageActions actions;
  final bool isSpeaking;

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 2),
      child: Row(
        children: <Widget>[
          // Les icônes vivent dans un `Wrap` : six cibles de 48 tiennent sur
          // la largeur d'un téléphone ordinaire, mais déborderaient d'un
          // écran étroit. Elles passent alors à la ligne, au lieu d'afficher
          // la bande rayée de débordement. « Sources » reste à droite, d'où
          // le `Row` autour.
          Expanded(
            child: Wrap(
              children: <Widget>[
                _ActionIcon(
                  icon: Icons.copy_rounded,
                  tooltip: 'Copier',
                  onPressed: () => actions.onCopy(message),
                ),
                _ActionIcon(
                  icon: message.rating == MessageRating.up
                      ? Icons.thumb_up
                      : Icons.thumb_up_outlined,
                  tooltip: 'Bonne réponse',
                  active: message.rating == MessageRating.up,
                  onPressed: () => actions.onRate(index, MessageRating.up),
                ),
                _ActionIcon(
                  icon: message.rating == MessageRating.down
                      ? Icons.thumb_down
                      : Icons.thumb_down_outlined,
                  tooltip: 'Mauvaise réponse',
                  active: message.rating == MessageRating.down,
                  onPressed: () => actions.onRate(index, MessageRating.down),
                ),
                _ActionIcon(
                  icon: isSpeaking
                      ? Icons.stop_rounded
                      : Icons.volume_up_outlined,
                  tooltip: isSpeaking
                      ? 'Arrêter la lecture'
                      : 'Lire à voix haute',
                  active: isSpeaking,
                  onPressed: () => actions.onSpeak(message),
                ),
                _ActionIcon(
                  icon: Icons.ios_share_rounded,
                  tooltip: 'Partager',
                  onPressed: () => actions.onShare(message),
                ),
                _ActionIcon(
                  icon: Icons.more_vert_rounded,
                  tooltip: 'Plus',
                  onPressed: () => _showMore(context),
                ),
              ],
            ),
          ),
          if (message.citations.isNotEmpty)
            TextButton(
              onPressed: () => actions.onShowSources(message),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(48, 48),
              ),
              child: Text(
                'Sources',
                style: TextStyle(
                  color: fox.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showMore(BuildContext context) {
    final fox = context.fox;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: fox.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: Icon(Icons.refresh_rounded, color: fox.textSecondary),
              title: Text(
                'Régénérer la réponse',
                style: TextStyle(color: fox.textPrimary),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                actions.onRegenerate(index);
              },
            ),
            ListTile(
              leading: Icon(Icons.notes_rounded, color: fox.textSecondary),
              title: Text(
                'Sélectionner le texte',
                style: TextStyle(color: fox.textPrimary),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showSelectableText(context, message.content);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;
    // 48 points de côté : le minimum qu'Android demande pour ce qui se
    // touche, et ces boutons sont les plus utilisés de l'application. Le
    // dessin reste à 19 : seule la zone sensible autour de lui s'élargit.
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      tooltip: tooltip,
      color: active ? fox.accent : fox.textSecondary,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      padding: EdgeInsets.zero,
      splashRadius: 22,
    );
  }
}

/// Ouvre le texte brut, sélectionnable caractère par caractère.
///
/// Le fil rend du Markdown : on n'y sélectionne pas un extrait précis. Cette
/// vue donne le texte tel quel, à copier par morceaux.
void _showSelectableText(BuildContext context, String content) {
  final fox = context.fox;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: fox.surfaceRaised,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: SingleChildScrollView(
          child: SelectableText(
            content,
            style: TextStyle(color: fox.textPrimary, fontSize: 15, height: 1.5),
          ),
        ),
      ),
    ),
  );
}

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

/// Dit pourquoi une réponse s'arrête là.
///
/// Un flux accepté puis écourté, un arrêt demandé, une erreur en cours de
/// route : le texte reçu reste affiché, mais rien ne doit laisser croire
/// qu'il est complet, ni à l'écran ni après un redémarrage.
class _OutcomeNote extends StatelessWidget {
  const _OutcomeNote({required this.message});

  final ChatMessage message;

  /// Motifs que les fournisseurs nomment le plus souvent, dits en clair.
  static const Map<String, String> _reasons = <String, String>{
    'max_output_tokens': 'la limite de longueur a été atteinte',
    'max_tokens': 'la limite de longueur a été atteinte',
    'content_filter': 'le fournisseur a filtré la suite',
    'length': 'la limite de longueur a été atteinte',
  };

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;
    final label = switch (message.outcome) {
      GenerationOutcome.incomplete => _incompleteLabel(),
      GenerationOutcome.cancelled => 'Réponse arrêtée.',
      GenerationOutcome.failed => 'Réponse interrompue par une erreur.',
      GenerationOutcome.complete => '',
    };
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.info_outline_rounded, size: 14, color: fox.textSecondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: fox.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  String _incompleteLabel() {
    if (message.content.isEmpty) {
      final reason = message.outcomeReason;
      final said = reason == null ? null : _reasons[reason];
      // Rien n'est arrivé : le dire, plutôt que laisser une bulle vide.
      return said == null
          ? 'Aucun texte reçu, la réponse s’est arrêtée avant de commencer.'
          : 'Aucun texte reçu : $said.';
    }
    final reason = message.outcomeReason;
    final said = reason == null ? null : _reasons[reason];
    if (said != null) {
      return 'Réponse écourtée : $said.';
    }
    // Motif inconnu : on le rapporte tel quel plutôt que d'en inventer un.
    return reason == null ? 'Réponse écourtée.' : 'Réponse écourtée ($reason).';
  }
}
