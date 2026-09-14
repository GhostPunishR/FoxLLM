// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:foxllm/core/storage/last_model_store.dart';
import 'package:foxllm/core/theme/fox_palette.dart';
import 'package:foxllm/core/ui/fox_mark.dart';
import 'package:foxllm/features/chat/attachments/attachment_picker.dart';
import 'package:foxllm/features/chat/attachments/attachment_resolver.dart';
import 'package:foxllm/features/chat/attachments/attachment_store.dart';
import 'package:foxllm/features/chat/chat_backend_host.dart';
import 'package:foxllm/features/chat/chat_modes.dart';
import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/features/chat/conversations/conversation_store.dart';
import 'package:foxllm/features/chat/dictation.dart';
import 'package:foxllm/features/chat/markdown/message_markdown.dart';
import 'package:foxllm/features/local_models/local_models_screen.dart';
import 'package:foxllm/features/settings/settings_screen.dart';
import 'package:foxllm/llm/backend/local_llm_backend.dart';
import 'package:foxllm/llm/model/chat_attachment.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm/llm/model/personalization.dart';
import 'package:foxllm/llm/personal_api/personal_api_chat_backend.dart';

part 'chat_top_bar.dart';
part 'chat_messages.dart';
part 'chat_composer.dart';
part 'chat_drawer.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
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

  /// Identifie le brouillon courant, texte et pièces jointes ensemble.
  ///
  /// Change dès qu'on quitte un fil : une sélection de fichier encore en
  /// cours ne vient alors pas déposer sa pièce jointe dans le fil suivant.
  int _draftEpoch = 0;

  /// Écritures de l'historique, regroupées.
  late final ConversationPersister _persister;
  bool _scrollScheduled = false;
  bool _restoringModel = false;
  String? _restorableModelPath;
  int _generationEpoch = 0;
  int _nextConversationId = 1;
  int? _activeConversationId;

  @override
  void initState() {
    super.initState();
    // Le magasin est saisi ici : `ref` n'est plus lisible dans `dispose()`,
    // où le dernier enregistrement doit pourtant encore partir.
    final store = ref.read(conversationStoreProvider);
    _persister = ConversationPersister(
      save: store.save,
      snapshot: () => List<ChatConversation>.of(_conversations),
      onError: _reportSaveFailure,
    );
    // Android peut tuer une application mise en arrière-plan sans passer par
    // `dispose()`. Comme les enregistrements sont désormais regroupés, il faut
    // écrire à ce moment-là, sans quoi les derniers fragments d'une génération
    // en cours seraient perdus.
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restoreSession());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _persister.flush();
    }
  }

  /// Le regroupeur n'appelle ceci qu'au premier échec d'une série : une panne
  /// de disque avertit une fois, pas à chaque groupe de fragments.
  void _reportSaveFailure(Object error) {
    if (!mounted) {
      return;
    }
    _showSnack('Conversation non enregistrée : $error');
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
    if (wasActive) {
      _clearDraft();
    }
    _persistConversations();
  }

  void _persistConversations({bool immediate = true}) {
    if (immediate) {
      _persister.flush();
    } else {
      _persister.schedule();
    }
  }

  @override
  void dispose() {
    unawaited(_dictation?.stop());
    WidgetsBinding.instance.removeObserver(this);
    _generationEpoch += 1;
    // Quitter l'écran en pleine génération ne doit pas perdre les fragments
    // déjà reçus mais pas encore écrits.
    _persister.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Abandonne le brouillon en cours, texte et pièces jointes.
  ///
  /// Les deux vont ensemble : n'effacer que le texte laissait les pièces
  /// jointes d'un fil partir avec le message suivant, écrit dans un autre.
  void _clearDraft() {
    _draftEpoch += 1;
    _inputController.clear();
    if (_pendingAttachments.isEmpty) {
      return;
    }
    final abandoned = List<ChatAttachment>.of(_pendingAttachments);
    _pendingAttachments.clear();
    _deleteUnreferencedAttachments(abandoned);
  }

  /// Efface les copies qu'aucun message n'utilise.
  ///
  /// Le filtrage n'est pas théorique : une pièce jointe déjà envoyée vit dans
  /// un message enregistré, et supprimer son fichier viderait la conversation
  /// où elle s'affiche.
  void _deleteUnreferencedAttachments(List<ChatAttachment> attachments) {
    if (attachments.isEmpty) {
      return;
    }
    final referenced = <String>{
      for (final conversation in _conversations)
        for (final message in conversation.messages)
          for (final attachment in message.attachments) attachment.path,
      for (final message in _messages)
        for (final attachment in message.attachments) attachment.path,
    };
    final removable = attachments
        .where((attachment) => !referenced.contains(attachment.path))
        .toList(growable: false);
    if (removable.isEmpty) {
      return;
    }
    unawaited(ref.read(attachmentStoreProvider).delete(removable));
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
    _clearDraft();
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
    _clearDraft();
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

    // Identité de cet envoi, prise avant la moindre attente. Le chargement du
    // modèle prend plusieurs secondes, pendant lesquelles l'utilisateur peut
    // ouvrir un autre fil ou en créer un : l'envoi reprenait alors avec
    // l'ancien texte et le nouvel historique.
    final generationEpoch = ++_generationEpoch;
    // Nul tant que le fil n'existe pas ; renseigné dès sa création ci-dessous,
    // pour que le garde suive le fil où le message vient d'être écrit.
    var conversationId = _activeConversationId;
    bool stillCurrent() =>
        mounted &&
        generationEpoch == _generationEpoch &&
        conversationId == _activeConversationId;

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
      if (!stillCurrent()) {
        // Fil abandonné pendant le chargement. Le brouillon de celui qui est
        // à l'écran maintenant appartient à l'utilisateur : on n'y touche pas.
        return;
      }
    }

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
    if (!stillCurrent()) {
      return;
    }

    setState(() {
      _ensureActiveConversation(text);
      conversationId = _activeConversationId;
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
        if (!stillCurrent()) {
          return;
        }
        setState(() {
          _messages[_messages.length - 1] = ChatMessage.assistant(response);
          // Un état intermédiaire que personne ne relira : il rejoint le
          // prochain enregistrement groupé plutôt que d'en déclencher un.
          _syncActiveConversation(immediate: false);
        });
        _scrollToBottom();
      }

      if (stillCurrent() && response.isEmpty) {
        _removeEmptyAssistantPlaceholder();
      }
    } catch (error) {
      if (!stillCurrent()) {
        return;
      }
      _removeEmptyAssistantPlaceholder();
      _showSnack('Génération impossible : $error');
    } finally {
      if (stillCurrent()) {
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

  void _syncActiveConversation({bool immediate = true}) {
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
    _persistConversations(immediate: immediate);
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
    // Un échec tardif, revenu après la fermeture de l'écran, n'a plus de
    // `context` où afficher quoi que ce soit : le message est abandonné
    // plutôt que de lever une exception par-dessus l'erreur d'origine.
    if (!mounted) {
      return;
    }
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
    // Le sélecteur système peut rester ouvert longtemps : le brouillon visé
    // est celui d'avant, pas celui qui sera à l'écran au retour.
    final draftEpoch = _draftEpoch;
    // Le sélecteur et le magasin sont saisis tant que `ref` est lisible. Le
    // nettoyage plus bas doit pouvoir effacer la copie même si l'écran a
    // disparu entre-temps, or `ref` lève une exception une fois démonté : la
    // copie serait alors restée sur l'appareil sans que rien n'y renvoie.
    final picker = ref.read(attachmentPickerProvider);
    final store = ref.read(attachmentStoreProvider);

    final PickedAttachment? picked;
    try {
      picked = await picker.pick(source);
    } on AttachmentException catch (error) {
      _showSnack(error.message);
      return;
    } catch (_) {
      _showSnack('Impossible de lire cette pièce jointe.');
      return;
    }
    if (picked == null || !mounted || draftEpoch != _draftEpoch) {
      return;
    }

    final ChatAttachment attachment;
    try {
      attachment = await store.save(
        name: picked.name,
        mimeType: picked.mimeType,
        bytes: picked.bytes,
      );
    } catch (_) {
      _showSnack('Impossible d’enregistrer cette pièce jointe.');
      return;
    }
    if (!mounted || draftEpoch != _draftEpoch) {
      // Le brouillon visé n'existe plus : la copie ne rejoint pas le fil
      // courant, et le fichier écrit entre-temps ne reste pas sur l'appareil.
      unawaited(store.delete(<ChatAttachment>[attachment]));
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
