// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/chat_attachment.dart';
import '../../core/llm/chat_message.dart';
import '../../core/llm/generation_settings.dart';
import '../../core/llm/personal_api_chat_backend.dart';
import '../../core/llm/last_model_store.dart';
import '../../core/llm/local_llm_backend.dart';
import '../../core/llm/personalization.dart';
import '../../core/theme/fox_palette.dart';
import 'chat_backend_host.dart';
import 'chat_conversation.dart';
import 'chat_modes.dart';
import 'conversation_store.dart';
import 'dictation.dart';
import 'message_markdown.dart';
import 'attachment_picker.dart';
import 'attachment_resolver.dart';
import 'attachment_store.dart';
import '../local_models/local_models_screen.dart';
import '../settings/settings_screen.dart';
import 'fox_mark.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = <ChatMessage>[];
  final List<ChatConversation> _conversations = <ChatConversation>[];

  /// Pièces jointes du message en cours de rédaction.
  final List<ChatAttachment> _pendingAttachments = <ChatAttachment>[];

  bool _isDictating = false;

  /// Dictée retenue dès son premier usage : `ref` n'est plus lisible dans
  /// `dispose()`, et l'écoute doit s'arrêter avec l'écran.
  Dictation? _dictation;

  /// Brouillon d'avant la dictée : le texte reconnu s'y ajoute au lieu de
  /// l'effacer, et chaque résultat partiel remplace le précédent.
  String _draftBeforeDictation = '';

  bool _isGenerating = false;
  bool _sending = false;
  bool _scrollScheduled = false;
  bool _restoringModel = false;
  String? _restorableModelPath;
  int _generationEpoch = 0;
  int _nextConversationId = 1;
  int? _activeConversationId;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreSession());
  }

  /// Recharge l'historique et déclare le dernier modèle utilisé.
  ///
  /// Le modèle n'est pas ouvert ici : le faire retarderait l'affichage du chat
  /// de plusieurs secondes. Il l'est au premier envoi, via
  /// `restoreModelIfNeeded()`.
  Future<void> _restoreSession() async {
    // Les instructions personnalisées partent en premier et sans attente :
    // elles accompagnent chaque envoi, et la lecture du stockage ne doit
    // dépendre ni de l'historique ni du modèle, qui peuvent échouer.
    unawaited(ref.read(personalizationProvider.notifier).resolved());
    // Les deux restaurations suivantes sont indépendantes : un historique
    // illisible ne doit pas empêcher de retrouver le modèle, et inversement.
    await _restoreConversations();
    await _restoreModelPath();
  }

  Future<void> _restoreConversations() async {
    final List<ChatConversation> conversations;
    try {
      conversations = await ref.read(conversationStoreProvider).load();
    } catch (_) {
      return;
    }
    if (mounted && conversations.isNotEmpty) {
      setState(() {
        _conversations
          ..clear()
          ..addAll(conversations);
        _nextConversationId =
            conversations
                .map((conversation) => conversation.id)
                .reduce((a, b) => a > b ? a : b) +
            1;
      });
    }
  }

  Future<void> _restoreModelPath() async {
    final String? lastModel;
    try {
      lastModel = await ref.read(lastModelStoreProvider).load();
    } catch (_) {
      return;
    }
    if (lastModel != null && mounted) {
      setState(() => _restorableModelPath = lastModel);
    }
  }

  Future<void> _renameConversation(int id, String title) async {
    final trimmed = title.trim();
    final conversation = _conversationById(id);
    if (trimmed.isEmpty || conversation == null) {
      return;
    }
    setState(() => conversation.title = trimmed);
    _persistConversations();
  }

  Future<void> _deleteConversation(int id) async {
    final conversation = _conversationById(id);
    if (conversation == null) {
      return;
    }

    final wasActive = _activeConversationId == id;
    if (wasActive && _isGenerating) {
      _generationEpoch += 1;
      await ref.read(chatBackendProvider).stop();
    }
    if (!mounted) {
      return;
    }

    // Les copies des pièces jointes ne servent plus à personne.
    unawaited(
      ref
          .read(attachmentStoreProvider)
          .delete(
            conversation.messages.expand((message) => message.attachments),
          ),
    );

    setState(() {
      _conversations.remove(conversation);
      if (wasActive) {
        _activeConversationId = null;
        _messages.clear();
        _isGenerating = false;
      }
    });
    _persistConversations();
  }

  void _persistConversations() {
    unawaited(
      ref
          .read(conversationStoreProvider)
          .save(List<ChatConversation>.of(_conversations)),
    );
  }

  @override
  void dispose() {
    unawaited(_dictation?.stop());
    _generationEpoch += 1;
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _newChat() async {
    _generationEpoch += 1;
    if (_isGenerating) {
      await ref.read(chatBackendProvider).stop();
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
      await ref.read(chatBackendProvider).stop();
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
    // `_isGenerating` n'est levé qu'une fois la requête partie : sans ce
    // second verrou, deux appuis rapprochés pendant l'ouverture du modèle ou
    // la lecture des réglages lanceraient deux envois, dont un serait perdu.
    if ((text.isEmpty && _pendingAttachments.isEmpty) ||
        _isGenerating ||
        _sending) {
      return;
    }
    _sending = true;
    try {
      await _send(text);
    } finally {
      _sending = false;
    }
  }

  Future<void> _send(String text) async {
    final backend = ref.read(chatBackendProvider);
    if (backend.loadedModelPath == null) {
      // Le modèle de la session précédente n'est ouvert qu'ici, pour ne pas
      // retarder l'affichage du chat au lancement.
      final restorable = _restorableModelPath;
      if (restorable == null) {
        _showModelRequired();
        return;
      }
      if (!await _restoreModel(backend, restorable)) {
        return;
      }
    }

    final generationEpoch = ++_generationEpoch;
    final attachments = List<ChatAttachment>.of(_pendingAttachments);
    final history = <ChatMessage>[
      ..._messages,
      ChatMessage(role: ChatRole.user, content: text, attachments: attachments),
    ];

    // Les instructions de Paramètres → Personnalisation ouvrent la requête,
    // sans rejoindre l'historique : elles sont globales et modifiables, la
    // conversation enregistrée ne doit pas figer celles du jour. Elles sont
    // lues telles que connues, sans attendre le stockage : sa lecture démarre
    // au lancement, bien avant qu'un message ait pu être écrit.
    final instructions = ref.read(personalizationProvider);
    final modes = ref.read(chatModesProvider);
    if (modes.webSearch &&
        !(backend is PersonalApiChatBackend && backend.supportsWebSearch)) {
      _showSnack(
        'La recherche web demande une API personnelle Google Gemini. '
        'Désactive-la ou change de fournisseur.',
      );
      return;
    }

    // Réflexion et personnalisation parlent au modèle de la même façon : une
    // seule consigne système, pour ne pas lui en empiler deux.
    final systemLines = <String>[
      if (instructions.isNotEmpty) instructions,
      if (modes.reasoning) reasoningInstruction,
    ];

    // Le fil garde des références aux pièces jointes ; la requête, elle, a
    // besoin de leur contenu.
    final List<ChatMessage> requestMessages;
    try {
      requestMessages = <ChatMessage>[
        if (systemLines.isNotEmpty)
          ChatMessage.system(systemLines.join('\n\n')),
        ...await resolveAttachments(
          history,
          store: ref.read(attachmentStoreProvider),
          supportsImages: backend is PersonalApiChatBackend,
        ),
      ];
    } on UnsupportedAttachmentException catch (error) {
      _showSnack(error.message);
      return;
    }
    if (!mounted || generationEpoch != _generationEpoch) {
      return;
    }

    setState(() {
      _ensureActiveConversation(text);
      _messages
        ..clear()
        ..addAll(history)
        ..add(const ChatMessage.assistant(''));
      _isGenerating = true;
      _syncActiveConversation();
    });
    _inputController.clear();
    _pendingAttachments.clear();
    _scrollToBottom();

    var response = '';
    try {
      final settings = GenerationSettings(
        maxTokens: modes.reasoning
            ? reasoningMaxTokens
            : const GenerationSettings().maxTokens,
        webSearch: modes.webSearch,
      );
      await for (final chunk in backend.generate(
        messages: requestMessages,
        settings: settings,
      )) {
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

  /// Ouvre le modèle mémorisé. Rend `false` si le chargement a échoué ou si
  /// l'écran a disparu entre-temps.
  Future<bool> _restoreModel(LocalLlmBackend backend, String path) async {
    setState(() => _restoringModel = true);
    try {
      await backend.loadModel(path);
    } catch (error) {
      if (mounted) {
        setState(() {
          _restoringModel = false;
          // Un modèle devenu illisible ne doit pas être retenté à chaque envoi.
          _restorableModelPath = null;
        });
        _showSnack('Chargement du modèle impossible : $error');
      }
      return false;
    }
    if (!mounted) {
      return false;
    }
    setState(() => _restoringModel = false);
    return true;
  }

  void _ensureActiveConversation(String firstMessage) {
    if (_activeConversationId != null) {
      return;
    }

    final conversation = ChatConversation(
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

  ChatConversation? _conversationById(int id) {
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
    _persistConversations();
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
    await ref.read(chatBackendProvider).stop();
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
    // Le streaming appelle cette méthode à chaque token : sans ce garde, chaque
    // token empile un post-frame callback et une animation de plus par frame.
    if (_scrollScheduled) {
      return;
    }
    _scrollScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
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

  Future<void> _toggleReasoning() async {
    await ref.read(chatModesProvider.notifier).toggleReasoning();
    if (!mounted) {
      return;
    }
    _showSnack(
      ref.read(chatModesProvider).reasoning
          ? 'Réflexion activée : le modèle exposera son raisonnement.'
          : 'Réflexion désactivée.',
    );
  }

  Future<void> _toggleWebSearch() async {
    await ref.read(chatModesProvider.notifier).toggleWebSearch();
    if (!mounted) {
      return;
    }
    if (!ref.read(chatModesProvider).webSearch) {
      _showSnack('Recherche web désactivée.');
      return;
    }
    final backend = ref.read(chatBackendProvider);
    final supported =
        backend is PersonalApiChatBackend && backend.supportsWebSearch;
    _showSnack(
      supported
          ? 'Recherche web activée : le modèle pourra consulter le web.'
          : 'Recherche web activée, mais le moteur en place ne sait pas '
                'consulter le web. Configure une API personnelle Google Gemini.',
    );
  }

  Future<void> _startDictation() async {
    if (_isDictating) {
      return;
    }
    _draftBeforeDictation = _inputController.text;
    setState(() => _isDictating = true);

    final Dictation dictation = _dictation ?? ref.read(dictationProvider);
    _dictation = dictation;
    final status = await dictation.start(onText: _onDictationText);
    if (!mounted) {
      return;
    }
    if (status == DictationStatus.listening) {
      return;
    }

    setState(() => _isDictating = false);
    _showSnack(
      status == DictationStatus.denied
          ? 'La dictée a besoin du micro. Autorise-le dans les réglages '
                'Android de FoxLLM.'
          : 'Aucune reconnaissance vocale disponible sur cet appareil.',
    );
  }

  void _onDictationText(String text) {
    if (!mounted || !_isDictating) {
      return;
    }
    final separator =
        _draftBeforeDictation.isEmpty || _draftBeforeDictation.endsWith(' ')
        ? ''
        : ' ';
    final combined = '$_draftBeforeDictation$separator$text';
    _inputController.value = TextEditingValue(
      text: combined,
      selection: TextSelection.collapsed(offset: combined.length),
    );
  }

  Future<void> _stopDictation() async {
    if (!_isDictating) {
      return;
    }
    setState(() => _isDictating = false);
    await _dictation?.stop();
  }

  void _showDictationHint() {
    if (_isDictating) {
      return;
    }
    _showSnack('Maintiens le bouton du micro pour dicter.');
  }

  void _showAddMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.fox.surfaceRaised,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: const Text('Joindre un fichier'),
                subtitle: const Text('Document ou code de l’appareil'),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_attach(AttachmentSource.file));
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Photos'),
                subtitle: const Text('Choisir une image de la galerie'),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_attach(AttachmentSource.gallery));
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Caméra'),
                subtitle: const Text('Prendre une photo'),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_attach(AttachmentSource.camera));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Choisit une pièce jointe et en range une copie avec la conversation.
  Future<void> _attach(AttachmentSource source) async {
    final PickedAttachment? picked;
    try {
      picked = await ref.read(attachmentPickerProvider).pick(source);
    } on AttachmentException catch (error) {
      _showSnack(error.message);
      return;
    } catch (_) {
      _showSnack('Impossible de lire cette pièce jointe.');
      return;
    }
    if (picked == null || !mounted) {
      return;
    }

    final ChatAttachment attachment;
    try {
      attachment = await ref
          .read(attachmentStoreProvider)
          .save(
            name: picked.name,
            mimeType: picked.mimeType,
            bytes: picked.bytes,
          );
    } catch (_) {
      _showSnack('Impossible d’enregistrer cette pièce jointe.');
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _pendingAttachments.add(attachment));
  }

  void _removePendingAttachment(ChatAttachment attachment) {
    setState(() => _pendingAttachments.remove(attachment));
    // La copie ne sert plus : elle n'a jamais rejoint de message.
    unawaited(
      ref.read(attachmentStoreProvider).delete(<ChatAttachment>[attachment]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
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
        onConversationRenamed: (id, title) =>
            unawaited(_renameConversation(id, title)),
        onConversationDeleted: (id) => unawaited(_deleteConversation(id)),
        onSettings: () {
          Navigator.of(context).pop();
          _openSettings();
        },
      ),
      body: Column(
        children: <Widget>[
          // Barre opaque : le fil de messages s'arrête dessous au lieu de
          // défiler derrière les deux boutons, où le texte devenait illisible.
          _ChatTopBar(
            onMenu: () => _scaffoldKey.currentState?.openDrawer(),
            onNewChat: () => unawaited(_newChat()),
          ),
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
          if (_restoringModel) const _RestoringModelBanner(),
          SafeArea(
            top: false,
            child: KeyedSubtree(
              key: const ValueKey<String>('chat-composer'),
              child: _Composer(
                controller: _inputController,
                isGenerating: _isGenerating,
                modes: ref.watch(chatModesProvider),
                attachments: _pendingAttachments,
                onRemoveAttachment: _removePendingAttachment,
                onReflection: () => unawaited(_toggleReasoning()),
                onSearch: () => unawaited(_toggleWebSearch()),
                onAdd: _showAddMenu,
                isDictating: _isDictating,
                onVoiceStart: () => unawaited(_startDictation()),
                onVoiceEnd: () => unawaited(_stopDictation()),
                onVoiceTap: _showDictationHint,
                onSend: () => unawaited(_sendMessage()),
                onStop: () => unawaited(_stopGeneration()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// En-tête du chat : menu latéral et nouveau chat, sur le fond du thème.
class _ChatTopBar extends StatelessWidget {
  const _ChatTopBar({required this.onMenu, required this.onNewChat});

  final VoidCallback onMenu;
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.fox.background,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: <Widget>[
              const SizedBox(width: 12),
              _TopButton(
                tooltip: 'Menu',
                onPressed: onMenu,
                child: const _MenuGlyph(),
              ),
              const Spacer(),
              _TopButton(
                tooltip: 'Nouveau chat',
                onPressed: onNewChat,
                child: const _NewChatGlyph(),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

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
                        : 'Message ou maintenir pour parler',
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
                    // Le micro reste offert même une fois le message commencé :
                    // dicter la fin d'une phrase est le cas le plus courant.
                    _DictationButton(
                      isDictating: isDictating,
                      onStart: onVoiceStart,
                      onEnd: onVoiceEnd,
                      onTap: onVoiceTap,
                    ),
                    if (isGenerating) ...<Widget>[
                      const SizedBox(width: 3),
                      _RoundComposerButton(
                        tooltip: 'Arrêter',
                        icon: Icons.stop_rounded,
                        onPressed: onStop,
                      ),
                    ] else
                      // Seul ce bouton dépend du brouillon : le reste de
                      // l'écran, liste de messages comprise, n'est pas
                      // reconstruit à chaque frappe.
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (context, value, child) {
                          // Une pièce jointe seule suffit à envoyer.
                          if (value.text.trim().isEmpty &&
                              attachments.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const SizedBox(width: 3),
                              _RoundComposerButton(
                                tooltip: 'Envoyer',
                                icon: Icons.arrow_upward_rounded,
                                filled: true,
                                onPressed: onSend,
                              ),
                            ],
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
          Container(width: 24, height: 2, color: context.fox.textPrimary),
          const SizedBox(height: 7),
          Container(width: 16, height: 2, color: context.fox.textPrimary),
        ],
      ),
    );
  }
}

class _NewChatGlyph extends StatelessWidget {
  const _NewChatGlyph();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 29,
      child: CustomPaint(painter: _NewChatPainter(context.fox.textPrimary)),
    );
  }
}

class _NewChatPainter extends CustomPainter {
  const _NewChatPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
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
  bool shouldRepaint(covariant _NewChatPainter oldDelegate) =>
      oldDelegate.color != color;
}

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
    final today = <ChatConversation>[];
    final lastWeek = <ChatConversation>[];
    final older = <ChatConversation>[];

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
                  _DrawerSectionHeader(
                    label: 'Aujourd’hui',
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
                  if (today.isEmpty && lastWeek.isEmpty && older.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
                      child: Text(
                        'Aucune conversation',
                        style: TextStyle(
                          color: fox.textSecondary,
                          fontSize: 16,
                        ),
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

  Widget _conversationTile(ChatConversation conversation) {
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

  int _dayDifference(DateTime from, DateTime to) {
    final fromDay = DateTime(from.year, from.month, from.day);
    final toDay = DateTime(to.year, to.month, to.day);
    return toDay.difference(fromDay).inDays;
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
