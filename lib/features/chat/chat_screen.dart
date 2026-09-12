import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/chat_message.dart';
import '../../core/llm/local_backend_provider.dart';
import '../local_models/local_models_screen.dart';
import '../settings/settings_screen.dart';
import 'fox_mark.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  static const background = Color(0xFF0B0B0B);
  static const composer = Color(0xFF242424);
  static const composerBorder = Color(0xFF3A3A3A);
  static const muted = Color(0xFF949494);
  static const blue = Color(0xFF5B8CFF);
  static const blueSurface = Color(0xFF202B43);
  static const blueBorder = Color(0xFF35558C);

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = <ChatMessage>[];
  final List<_ChatConversation> _conversations = <_ChatConversation>[];

  bool _isGenerating = false;
  int _generationEpoch = 0;
  int _nextConversationId = 1;
  int? _activeConversationId;

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _generationEpoch += 1;
    _inputController
      ..removeListener(_onInputChanged)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _newChat() async {
    _generationEpoch += 1;
    if (_isGenerating) {
      await ref.read(localLlmBackendProvider).stop();
    }
    if (!mounted) {
      return;
    }
    _syncActiveConversation();
    setState(() {
      _activeConversationId = null;
      _messages.clear();
      _isGenerating = false;
    });
    _inputController.clear();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _selectConversation(int id) async {
    _generationEpoch += 1;
    if (_isGenerating) {
      await ref.read(localLlmBackendProvider).stop();
    }
    if (!mounted) {
      return;
    }

    _syncActiveConversation();
    final conversation = _conversationById(id);
    if (conversation == null) {
      return;
    }

    setState(() {
      _activeConversationId = id;
      _messages
        ..clear()
        ..addAll(conversation.messages);
      _isGenerating = false;
    });
    _inputController.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    _scrollToBottom();
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isGenerating) {
      return;
    }

    final backend = ref.read(localLlmBackendProvider);
    if (backend.loadedModelPath == null) {
      _showModelRequired();
      return;
    }

    final generationEpoch = ++_generationEpoch;
    final requestMessages = <ChatMessage>[..._messages, ChatMessage.user(text)];

    setState(() {
      _ensureActiveConversation(text);
      _messages
        ..clear()
        ..addAll(requestMessages)
        ..add(const ChatMessage.assistant(''));
      _isGenerating = true;
      _syncActiveConversation();
    });
    _inputController.clear();
    _scrollToBottom();

    var response = '';
    try {
      await for (final chunk in backend.generate(messages: requestMessages)) {
        response += chunk;
        if (!mounted || generationEpoch != _generationEpoch) {
          return;
        }
        setState(() {
          _messages[_messages.length - 1] = ChatMessage.assistant(response);
          _syncActiveConversation();
        });
        _scrollToBottom();
      }

      if (mounted && generationEpoch == _generationEpoch && response.isEmpty) {
        _removeEmptyAssistantPlaceholder();
      }
    } catch (error) {
      if (!mounted || generationEpoch != _generationEpoch) {
        return;
      }
      _removeEmptyAssistantPlaceholder();
      _showSnack('Génération impossible : $error');
    } finally {
      if (mounted && generationEpoch == _generationEpoch) {
        setState(() {
          _isGenerating = false;
          _syncActiveConversation();
        });
      }
    }
  }

  void _ensureActiveConversation(String firstMessage) {
    if (_activeConversationId != null) {
      return;
    }

    final conversation = _ChatConversation(
      id: _nextConversationId++,
      title: _conversationTitle(firstMessage),
      updatedAt: DateTime.now(),
      messages: <ChatMessage>[],
    );
    _conversations.insert(0, conversation);
    _activeConversationId = conversation.id;
  }

  String _conversationTitle(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 42) {
      return normalized;
    }
    return '${normalized.substring(0, 39)}…';
  }

  _ChatConversation? _conversationById(int id) {
    for (final conversation in _conversations) {
      if (conversation.id == id) {
        return conversation;
      }
    }
    return null;
  }

  void _syncActiveConversation() {
    final id = _activeConversationId;
    if (id == null) {
      return;
    }
    final conversation = _conversationById(id);
    if (conversation == null) {
      return;
    }
    conversation
      ..messages = <ChatMessage>[..._messages]
      ..updatedAt = DateTime.now();

    _conversations
      ..remove(conversation)
      ..insert(0, conversation);
  }

  void _removeEmptyAssistantPlaceholder() {
    if (_messages.isEmpty ||
        _messages.last.role != ChatRole.assistant ||
        _messages.last.content.isNotEmpty) {
      return;
    }
    setState(() {
      _messages.removeLast();
      _syncActiveConversation();
    });
  }

  Future<void> _stopGeneration() async {
    await ref.read(localLlmBackendProvider).stop();
  }

  void _showModelRequired() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Charge un modèle GGUF avant de discuter.'),
          action: SnackBarAction(label: 'Modèles', onPressed: _openLocalModels),
        ),
      );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      unawaited(
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  void _openLocalModels() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const LocalModelsScreen()),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const SettingsScreen()),
    );
  }

  void _showReflectionInfo() {
    _showSnack(
      'Le mode Réflexion sera relié aux paramètres du modèle ensuite.',
    );
  }

  void _showSearchInfo() {
    _showSnack('La recherche web sera ajoutée au backend outils de FoxGPT.');
  }

  void _showVoiceInfo() {
    _showSnack('La dictée vocale sera ajoutée dans une prochaine étape.');
  }

  void _showAddMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF191919),
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.memory_outlined),
                title: const Text('Modèles locaux'),
                subtitle: const Text('Importer ou charger un fichier GGUF'),
                onTap: () {
                  Navigator.of(context).pop();
                  _openLocalModels();
                },
              ),
              const ListTile(
                enabled: false,
                leading: Icon(Icons.attach_file),
                title: Text('Joindre un fichier'),
                subtitle: Text('Bientôt disponible'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasDraft = _inputController.text.trim().isNotEmpty;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: background,
      resizeToAvoidBottomInset: true,
      drawerScrimColor: Colors.black54,
      drawer: _FoxDrawer(
        conversations: _conversations,
        activeConversationId: _activeConversationId,
        onNewChat: () {
          Navigator.of(context).pop();
          unawaited(_newChat());
        },
        onConversationSelected: (id) {
          Navigator.of(context).pop();
          unawaited(_selectConversation(id));
        },
        onSettings: () {
          Navigator.of(context).pop();
          _openSettings();
        },
      ),
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: KeyedSubtree(
                    key: const ValueKey<String>('chat-content'),
                    child: _messages.isEmpty
                        ? const _WelcomeState()
                        : _MessageList(
                            messages: _messages,
                            controller: _scrollController,
                          ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: KeyedSubtree(
                    key: const ValueKey<String>('chat-composer'),
                    child: _Composer(
                      controller: _inputController,
                      isGenerating: _isGenerating,
                      hasDraft: hasDraft,
                      onReflection: _showReflectionInfo,
                      onSearch: _showSearchInfo,
                      onAdd: _showAddMenu,
                      onVoice: _showVoiceInfo,
                      onSend: () => unawaited(_sendMessage()),
                      onStop: () => unawaited(_stopGeneration()),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 18,
            left: 12,
            child: _TopButton(
              tooltip: 'Menu',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              child: const _MenuGlyph(),
            ),
          ),
          Positioned(
            top: 18,
            right: 12,
            child: _TopButton(
              tooltip: 'Nouveau chat',
              onPressed: () => unawaited(_newChat()),
              child: const _NewChatGlyph(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatConversation {
  _ChatConversation({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
  });

  final int id;
  final String title;
  DateTime updatedAt;
  List<ChatMessage> messages;
}

class _WelcomeState extends StatelessWidget {
  const _WelcomeState();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: EdgeInsets.only(top: constraints.maxHeight * 0.39),
          child: const Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                FoxMark(size: 46),
                SizedBox(height: 22),
                SizedBox(
                  width: 300,
                  child: Text(
                    "Salut ! Qu'aimeriez-vous\ndiscuter aujourd'hui ?",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
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
      padding: const EdgeInsets.fromLTRB(18, 72, 18, 24),
      itemCount: messages.length,
      itemBuilder: (context, index) {
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
                    color: const Color(0xFF282828),
                    borderRadius: BorderRadius.circular(22),
                  )
                : null,
            child: message.content.isEmpty
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    message.content,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.45,
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.isGenerating,
    required this.hasDraft,
    required this.onReflection,
    required this.onSearch,
    required this.onAdd,
    required this.onVoice,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool isGenerating;
  final bool hasDraft;
  final VoidCallback onReflection;
  final VoidCallback onSearch;
  final VoidCallback onAdd;
  final VoidCallback onVoice;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _ChatScreenState.composer,
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: _ChatScreenState.composerBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 13, 12, 11),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  keyboardAppearance: Brightness.dark,
                  style: const TextStyle(color: Colors.white, fontSize: 17),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Message ou maintenir pour parler',
                    hintStyle: TextStyle(
                      color: _ChatScreenState.muted,
                      fontSize: 17,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 2),
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
                                onPressed: onReflection,
                              ),
                              const SizedBox(width: 8),
                              _ToolChip(
                                icon: Icons.language,
                                label: 'Rechercher',
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
                    if (isGenerating)
                      _RoundComposerButton(
                        tooltip: 'Arrêter',
                        icon: Icons.stop_rounded,
                        onPressed: onStop,
                      )
                    else if (hasDraft)
                      _RoundComposerButton(
                        tooltip: 'Envoyer',
                        icon: Icons.arrow_upward_rounded,
                        filled: true,
                        onPressed: onSend,
                      )
                    else
                      _RoundComposerButton(
                        tooltip: 'Parler',
                        icon: Icons.graphic_eq_rounded,
                        onPressed: onVoice,
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

class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _ChatScreenState.blueSurface,
      shape: StadiumBorder(
        side: BorderSide(color: _ChatScreenState.blueBorder),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: _ChatScreenState.blue),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: _ChatScreenState.blue,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
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
                color: filled ? Colors.white : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.7),
              ),
              child: Icon(
                icon,
                color: filled ? Colors.black : Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopButton extends StatelessWidget {
  const _TopButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 42,
        child: InkResponse(
          radius: 22,
          onTap: onPressed,
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _MenuGlyph extends StatelessWidget {
  const _MenuGlyph();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(width: 24, height: 2, color: Colors.white),
          const SizedBox(height: 7),
          Container(width: 16, height: 2, color: Colors.white),
        ],
      ),
    );
  }
}

class _NewChatGlyph extends StatelessWidget {
  const _NewChatGlyph();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 29,
      child: CustomPaint(painter: _NewChatPainter()),
    );
  }
}

class _NewChatPainter extends CustomPainter {
  const _NewChatPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final bubble = Path()
      ..moveTo(5, 4)
      ..quadraticBezierTo(3, 4, 3, 7)
      ..lineTo(3, 21)
      ..quadraticBezierTo(3, 24, 6, 24)
      ..lineTo(18, 24)
      ..lineTo(24, 28)
      ..lineTo(23, 23)
      ..quadraticBezierTo(26, 22, 26, 19)
      ..lineTo(26, 7)
      ..quadraticBezierTo(26, 4, 23, 4)
      ..close();
    canvas.drawPath(bubble, paint);

    canvas
      ..drawLine(const Offset(14.5, 8), const Offset(14.5, 20), paint)
      ..drawLine(const Offset(8.5, 14), const Offset(20.5, 14), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FoxDrawer extends StatefulWidget {
  const _FoxDrawer({
    required this.conversations,
    required this.activeConversationId,
    required this.onNewChat,
    required this.onConversationSelected,
    required this.onSettings,
  });

  final List<_ChatConversation> conversations;
  final int? activeConversationId;
  final VoidCallback onNewChat;
  final ValueChanged<int> onConversationSelected;
  final VoidCallback onSettings;

  @override
  State<_FoxDrawer> createState() => _FoxDrawerState();
}

class _FoxDrawerState extends State<_FoxDrawer> {
  static const _drawerColor = Color(0xFF0D0D0D);
  static const _searchColor = Color(0xFF242424);
  static const _muted = Color(0xFF969696);

  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  List<_ChatConversation> get _filteredConversations {
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
    final width = math.min(MediaQuery.sizeOf(context).width * 0.86, 360.0);
    final conversations = _filteredConversations;
    final today = <_ChatConversation>[];
    final lastWeek = <_ChatConversation>[];
    final older = <_ChatConversation>[];

    for (final conversation in conversations) {
      final age = _dayDifference(conversation.updatedAt, DateTime.now());
      if (age <= 0) {
        today.add(conversation);
      } else if (age <= 7) {
        lastWeek.add(conversation);
      } else {
        older.add(conversation);
      }
    }

    return Drawer(
      width: width,
      shape: const RoundedRectangleBorder(),
      backgroundColor: _drawerColor,
      child: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: _searchColor,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: TextField(
                  controller: _searchController,
                  autofocus: false,
                  keyboardAppearance: Brightness.dark,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: 'Rechercher dans les chats',
                    hintStyle: TextStyle(
                      color: _muted,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: _muted,
                      size: 27,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                children: <Widget>[
                  _DrawerSectionHeader(
                    label: 'Aujourd’hui',
                    trailing: IconButton(
                      tooltip: 'Nouveau chat',
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onNewChat,
                      icon: const Icon(
                        Icons.add_comment_outlined,
                        color: _muted,
                        size: 21,
                      ),
                    ),
                  ),
                  if (today.isEmpty && lastWeek.isEmpty && older.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(2, 18, 2, 10),
                      child: Text(
                        'Aucune conversation',
                        style: TextStyle(color: _muted, fontSize: 16),
                      ),
                    )
                  else
                    ...today.map(_conversationTile),
                  if (lastWeek.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 14),
                    const _DrawerSectionHeader(label: '7 jours'),
                    ...lastWeek.map(_conversationTile),
                  ],
                  if (older.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 14),
                    const _DrawerSectionHeader(label: 'Plus tôt'),
                    ...older.map(_conversationTile),
                  ],
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFF1B1B1B)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: widget.onSettings,
                  borderRadius: BorderRadius.circular(14),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.settings_outlined,
                          color: Colors.white,
                          size: 25,
                        ),
                        SizedBox(width: 13),
                        Expanded(
                          child: Text(
                            'Paramètres',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(Icons.more_horiz, color: _muted, size: 24),
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

  Widget _conversationTile(_ChatConversation conversation) {
    final selected = conversation.id == widget.activeConversationId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? const Color(0xFF1B1B1B) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => widget.onConversationSelected(conversation.id),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
            child: Text(
              conversation.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFE9E9E9),
                fontSize: 17,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _dayDifference(DateTime from, DateTime to) {
    final fromDay = DateTime(from.year, from.month, from.day);
    final toDay = DateTime(to.year, to.month, to.day);
    return toDay.difference(fromDay).inDays;
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
              style: const TextStyle(
                color: Color(0xFF949494),
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
