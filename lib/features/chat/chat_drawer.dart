// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

// Menu latéral : recherche, conversations, renommage et suppression.
// Partie de la bibliothèque `chat_screen.dart` : ces widgets ne servent
// qu'à cet écran et restent donc privés, sans changer de nom ni d'accès.

part of 'chat_screen.dart';

class _FoxDrawer extends StatefulWidget {
  const _FoxDrawer({
    required this.conversations,
    required this.activeConversationId,
    required this.onNewChat,
    required this.onConversationSelected,
    required this.onConversationRenamed,
    required this.onConversationDeleted,
    required this.onSettings,
  });

  final List<ChatConversation> conversations;
  final int? activeConversationId;
  final VoidCallback onNewChat;
  final ValueChanged<int> onConversationSelected;
  final void Function(int id, String title) onConversationRenamed;
  final ValueChanged<int> onConversationDeleted;
  final VoidCallback onSettings;

  @override
  State<_FoxDrawer> createState() => _FoxDrawerState();
}

class _FoxDrawerState extends State<_FoxDrawer> {
  final _searchController = TextEditingController();

  /// Réveil au prochain minuit, quand les tranches changent de sens.
  ///
  /// Sans lui, une application laissée ouverte la nuit continue de classer
  /// d'après la veille : le fil d'hier soir reste sous « Aujourd'hui » jusqu'à
  /// ce qu'autre chose provoque une reconstruction.
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    // Une seconde de marge : un réveil pile à minuit peut se produire une
    // fraction de seconde trop tôt et relire la date de la veille.
    final delay =
        nextMidnight(now).difference(now) + const Duration(seconds: 1);
    _midnight = Timer(delay, () {
      if (!mounted) {
        return;
      }
      setState(_scheduleMidnight);
    });
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _midnight?.cancel();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  List<ChatConversation> get _filteredConversations {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return widget.conversations;
    }
    return widget.conversations
        .where(
          (conversation) => conversation.title.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;
    final width = math.min(MediaQuery.sizeOf(context).width * 0.86, 360.0);
    final conversations = _filteredConversations;

    // Un seul relevé de l'heure pour toute la construction : deux appels
    // encadrant minuit rangeraient deux conversations de la même minute dans
    // deux tranches différentes.
    final now = DateTime.now();
    final grouped = <ConversationAge, List<ChatConversation>>{};
    for (final conversation in conversations) {
      grouped
          .putIfAbsent(
            conversationAge(conversation.updatedAt, now),
            () => <ChatConversation>[],
          )
          .add(conversation);
    }

    return Drawer(
      width: width,
      shape: const RoundedRectangleBorder(),
      backgroundColor: fox.background,
      child: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: fox.surfaceInput,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: TextField(
                  controller: _searchController,
                  autofocus: false,
                  keyboardAppearance: Theme.of(context).brightness,
                  style: TextStyle(color: fox.textPrimary, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Rechercher dans les chats',
                    hintStyle: TextStyle(
                      color: fox.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: fox.textSecondary,
                      size: 27,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                children: <Widget>[
                  // En-tête fixe : il porte le bouton « + », donc il reste
                  // quoi qu'il arrive. Les tranches de dates, elles, ne
                  // s'affichent que si elles contiennent quelque chose : un
                  // « Aujourd'hui » vide au-dessus des conversations d'hier
                  // laissait croire qu'elles dataient d'aujourd'hui.
                  _DrawerSectionHeader(
                    label: 'Chats',
                    trailing: IconButton(
                      tooltip: 'Nouveau chat',
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onNewChat,
                      icon: Icon(
                        Icons.add_comment_outlined,
                        color: fox.textSecondary,
                        size: 21,
                      ),
                    ),
                  ),
                  if (grouped.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
                      child: Text(
                        'Aucune conversation',
                        style: TextStyle(
                          color: fox.textSecondary,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  for (final age in ConversationAge.values)
                    if (grouped[age] case final section?) ...<Widget>[
                      const SizedBox(height: 6),
                      _DrawerSectionHeader(label: age.label),
                      for (final conversation in section)
                        _conversationTile(conversation, now),
                    ],
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: fox.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: widget.onSettings,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 13,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.settings_outlined,
                          color: fox.textPrimary,
                          size: 25,
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Text(
                            'Paramètres',
                            style: TextStyle(
                              color: fox.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.more_horiz,
                          color: fox.textSecondary,
                          size: 24,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _conversationTile(ChatConversation conversation, DateTime now) {
    final fox = context.fox;
    final selected = conversation.id == widget.activeConversationId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? fox.surfaceSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => widget.onConversationSelected(conversation.id),
          onLongPress: () => _showConversationActions(conversation),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.only(left: 2, top: 2, bottom: 2),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    conversation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? fox.textPrimary : fox.textSecondary,
                      fontSize: 17,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // La date exacte, pour que la tranche n'ait pas à tout dire.
                Text(
                  conversationStamp(conversation.updatedAt, now),
                  style: TextStyle(color: fox.textTertiary, fontSize: 13),
                ),
                IconButton(
                  tooltip: 'Actions de la conversation',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _showConversationActions(conversation),
                  icon: Icon(
                    Icons.more_horiz,
                    color: fox.textTertiary,
                    size: 21,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Renommer ou supprimer, depuis le bouton « … » ou un appui long.
  Future<void> _showConversationActions(ChatConversation conversation) async {
    final action = await showModalBottomSheet<_ConversationAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Renommer'),
              onTap: () =>
                  Navigator.of(context).pop(_ConversationAction.rename),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Supprimer',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () =>
                  Navigator.of(context).pop(_ConversationAction.delete),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _ConversationAction.rename:
        await _promptRename(conversation);
      case _ConversationAction.delete:
        await _confirmDelete(conversation);
    }
  }

  Future<void> _promptRename(ChatConversation conversation) async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initialTitle: conversation.title),
    );

    if (title != null && title.trim().isNotEmpty) {
      widget.onConversationRenamed(conversation.id, title);
    }
  }

  Future<void> _confirmDelete(ChatConversation conversation) async {
    // L'historique étant conservé sur l'appareil, une suppression accidentelle
    // ne se rattrape pas en fermant l'application.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la conversation ?'),
        content: Text(
          '« ${conversation.title} » sera définitivement supprimée de '
          'l’appareil.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      widget.onConversationDeleted(conversation.id);
    }
  }
}

enum _ConversationAction { rename, delete }

/// Dialogue de renommage.
///
/// Le contrôleur appartient à ce widget : le libérer depuis l'appelant, dès
/// le retour de `showDialog`, le détruirait alors que le champ est encore
/// affiché pendant l'animation de fermeture.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialTitle,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Renommer la conversation'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'Nom de la conversation'),
        onSubmitted: (_) => _submit(),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Renommer')),
      ],
    );
  }
}

class _DrawerSectionHeader extends StatelessWidget {
  const _DrawerSectionHeader({required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: context.fox.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
