// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:foxllm/core/storage/last_model_store.dart';
import 'package:foxllm/core/ui/external_link.dart';
import 'package:foxllm/core/theme/fox_palette.dart';
import 'package:foxllm/core/ui/fox_mark.dart';
import 'package:foxllm/features/chat/attachments/attachment_picker.dart';
import 'package:foxllm/features/chat/attachments/attachment_resolver.dart';
import 'package:foxllm/features/chat/attachments/attachment_store.dart';
import 'package:foxllm/features/chat/chat_backend_host.dart';
import 'package:foxllm/features/chat/chat_modes.dart';
import 'package:foxllm/features/chat/conversations/chat_conversation.dart';
import 'package:foxllm/features/chat/conversations/conversation_date.dart';
import 'package:foxllm/features/chat/conversations/conversation_housekeeping.dart';
import 'package:foxllm/features/chat/conversations/conversation_store.dart';
import 'package:foxllm/features/chat/dictation.dart';
import 'package:foxllm/features/chat/markdown/message_markdown.dart';
import 'package:foxllm/features/chat/speech.dart';
import 'package:foxllm/features/local_models/local_models_screen.dart';
import 'package:foxllm/features/settings/settings_screen.dart';
import 'package:foxllm/llm/backend/local_llm_backend.dart';
import 'package:foxllm/llm/model/chat_attachment.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/citation.dart';
import 'package:foxllm/llm/model/generation_settings.dart';
import 'package:foxllm/llm/model/personalization.dart';
import 'package:foxllm/llm/personal_api/personal_api_chat_backend.dart';
import 'package:foxllm/llm/personal_api/personal_api_settings.dart';

part 'chat_top_bar.dart';
part 'chat_messages.dart';
part 'chat_composer.dart';
part 'chat_drawer.dart';

/// Écart minimal entre deux peintures du message en cours de réception.
///
/// Vingt images par seconde : assez pour que le texte paraisse s'écrire, et
/// dix à vingt fois moins de travail qu'une peinture par fragment reçu. Un
/// fournisseur rapide en envoie plusieurs dizaines par seconde, dont personne
/// ne peut lire la différence.
const _streamPaintInterval = Duration(milliseconds: 50);

/// Ce qu'un envoi a réuni avant de partir.
///
/// [history] est le fil tel qu'il sera affiché ; [requestMessages] ce qui part
/// au modèle, consigne système et contenu des pièces jointes compris. Les deux
/// diffèrent à dessein : la conversation enregistrée ne doit pas figer les
/// instructions du jour.
class _PreparedSend {
  const _PreparedSend({
    required this.history,
    required this.requestMessages,
    required this.modes,
  });

  final List<ChatMessage> history;
  final List<ChatMessage> requestMessages;
  final ChatModes modes;
}

/// Ce qu'un envoi engagé laisse derrière lui.
///
/// [conversationId] peut être celui d'un fil que ce message vient de créer :
/// l'envoi doit alors suivre cette nouvelle identité, pas celle qu'il visait.
/// [replaced] est la version que le remplacement efface, `null` quand l'envoi
/// n'en remplace aucune.
class _CommittedSend {
  const _CommittedSend({required this.conversationId, required this.replaced});

  final int? conversationId;
  final List<ChatMessage>? replaced;
}

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

  /// Réponse actuellement lue à voix haute, `null` au repos.
  String? _speakingText;

  /// Synthèse vocale retenue dès son premier usage : `ref` n'est plus lisible
  /// dans `dispose()`, et la lecture doit s'arrêter avec l'écran.
  Speech? _speech;

  /// Message utilisateur en cours de modification, et son brouillon.
  ///
  /// L'indice seul ne suffit pas à désigner un message : il vaut pour le fil
  /// affiché au moment où la modification a commencé. Ouvrir un autre fil
  /// faisait porter le texte saisi sur son message de même rang.
  int? _editingIndex;
  int? _editingConversationId;

  /// Contenu du message au début de la modification.
  ///
  /// Vérifié à la validation : la structure du fil a pu changer entre-temps,
  /// et l'indice désignerait alors un autre message.
  String? _editingOriginal;
  final _editController = TextEditingController();

  /// Messages écrits pendant une réponse, envoyés chacun à leur tour.
  ///
  /// Écrire pendant que le modèle répond est courant : plutôt que de refuser
  /// l'envoi ou d'interrompre la réponse en cours, le message attend son tour.
  final List<_Outgoing> _queued = <_Outgoing>[];

  /// Change chaque fois que la file est abandonnée.
  ///
  /// Un message sorti de la file revient en tête s'il est refusé. Sans ce
  /// repère, ce retour ressuscitait une file que la navigation venait de
  /// vider, et le message repartait dans le fil suivant.
  int _queueEpoch = 0;

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

  /// Génération que l'utilisateur a explicitement arrêtée.
  int _cancelledEpoch = -1;

  /// Note que la génération en cours est interrompue, puis l'invalide.
  ///
  /// Quitter un fil pendant sa réponse arrête le moteur : le flux se termine
  /// alors normalement, et rien ne distinguerait plus cette interruption d'une
  /// réponse allée au bout.
  void _abandonGeneration() {
    if (_isGenerating) {
      _cancelledEpoch = _generationEpoch;
    }
    _generationEpoch += 1;
  }

  /// Époque de la dernière génération lancée dans chaque conversation.
  ///
  /// Une génération abandonnée se termine parfois longtemps après qu'on a
  /// quitté son fil. Elle ne doit alors le réparer que si personne n'y a
  /// relancé une réponse entre-temps : sans ce repère, une opération périmée
  /// écrasait la plus récente.
  final Map<int, int> _lastGeneration = <int, int>{};
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

  /// Relecture de l'historique, attendue avant toute mutation.
  ///
  /// Elle remplace la liste en mémoire : un envoi parti avant elle serait
  /// effacé par son arrivée, et la liste vide du lancement écraserait le
  /// fichier si une sauvegarde partait entre-temps.
  ///
  /// Porte sur l'historique seul, et non sur le reste de la restauration : le
  /// chemin du dernier modèle est sans rapport avec la liste des
  /// conversations, et un envoi n'a aucune raison de l'attendre.
  final _historyRestored = Completer<void>();

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
    List<ChatConversation> conversations;
    try {
      conversations = await ref.read(conversationStoreProvider).load();
    } on ConversationLoadException catch (error) {
      // Le fichier n'a pas pu être relu en entier. Tout enregistrement
      // ultérieur le remplacerait par ce que l'écran a en mémoire, donc par
      // moins que ce qu'il contient : mieux vaut ne plus rien écrire.
      //
      // Les conversations tout de même lisibles sont affichées : les cacher
      // n'aiderait personne, et rien ne sera réécrit de toute façon.
      _persister.abandon();
      conversations = error.recovered;
      if (mounted) {
        // Le message vient de l'exception, jamais de sa cause technique :
        // celle de `jsonDecode` cite un extrait du fichier, donc des
        // morceaux de conversation.
        _showSnack(
          '${error.message} Les conversations de cette session ne seront pas '
          'enregistrées.',
        );
      }
      if (conversations.isEmpty) {
        _openHistoryGate();
        return;
      }
    } catch (_) {
      // Panne de lecture qui ne vient pas du contenu : disque, permissions.
      // Même conclusion, et toujours sans citer la cause, qui peut porter un
      // chemin ou un extrait de fichier.
      _persister.abandon();
      if (mounted) {
        _showSnack(
          'Lecture de l’historique impossible. Les conversations de cette '
          'session ne seront pas enregistrées.',
        );
      }
      _openHistoryGate();
      return;
    }
    if (mounted && conversations.isNotEmpty) {
      setState(() {
        // Un envoi attend la relecture, la liste est donc vide ici. L'insérer
        // devant plutôt que remplacer garde les deux si cela changeait.
        _conversations.insertAll(0, conversations);
        _nextConversationId =
            <int>[
              _nextConversationId - 1,
              ...conversations.map((conversation) => conversation.id),
            ].reduce((a, b) => a > b ? a : b) +
            1;
      });
    }
    // L'historique est en place : les écritures peuvent partir, y compris
    // celles demandées pendant l'attente.
    _persister.release();
    _openHistoryGate();
  }

  /// Libère les envois qui attendaient la relecture, réussie ou non.
  ///
  /// Une lecture en échec ne doit pas bloquer l'application : elle interdit
  /// les écritures, pas l'usage.
  void _openHistoryGate() {
    if (!_historyRestored.isCompleted) {
      _historyRestored.complete();
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
    if (wasActive) {
      _dropQueue();
      _stopSpeaking();
      _forgetEdit();
    }
    if (wasActive && _isGenerating) {
      _abandonGeneration();
      await ref.read(chatBackendProvider).stop();
    }
    if (!mounted) {
      return;
    }

    // Les copies des pièces jointes ne servent plus à personne, y compris
    // celles d'une version conservée : elles n'étaient citées que par cette
    // conversation, et resteraient sinon sur le disque sans que rien ne
    // puisse plus les rouvrir ni les effacer.
    unawaited(
      ref.read(attachmentStoreProvider).delete(conversation.attachments),
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
    // L'écouteur part avant l'arrêt : `stop()` remet l'observable à zéro, et
    // le rappel toucherait alors un écran en cours de destruction.
    _speech?.speaking.removeListener(_onSpeakingChanged);
    unawaited(_speech?.stop());
    _editController.dispose();
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
    final abandoned = List<ChatAttachment>.of(_pendingAttachments);
    _pendingAttachments.clear();
    _deleteUnreferencedAttachments(abandoned);
    _dropQueue();
  }

  /// Coupe la lecture à voix haute, quand le message lu quitte l'écran.
  ///
  /// La voix d'Android ne s'arrête pas parce que la bulle disparaît : un fil
  /// quitté continuait de se faire lire, et plus rien ne permettait de
  /// l'interrompre, puisque le bouton qui l'aurait fait était parti avec le
  /// message.
  ///
  /// Ne réveille pas le moteur vocal s'il n'a jamais servi : il n'est monté
  /// qu'au premier appui sur le bouton de lecture.
  void _stopSpeaking() {
    // Pas de garde sur « une lecture est en cours » : pendant la préparation
    // de la voix, rien ne parle encore, et c'est précisément le moment où
    // l'annulation doit passer. Le service, lui, sait l'invalider.
    final speech = _speech;
    if (speech == null) {
      return;
    }
    unawaited(speech.stop());
  }

  /// Abandonne les messages en attente : ils appartiennent au fil quitté.
  ///
  /// À appeler avant la moindre attente. Quitter un fil commence par arrêter
  /// le moteur, et cet arrêt termine la réponse en cours : la file repartirait
  /// alors toute seule, dans le fil suivant.
  void _dropQueue() {
    // Compté même sur une file déjà vide : un envoi parti de la file est en
    // vol, et sa réinsertion après un refus doit être refusée elle aussi.
    _queueEpoch += 1;
    if (_queued.isEmpty) {
      return;
    }
    final abandoned = <ChatAttachment>[
      for (final queued in _queued) ...queued.attachments,
    ];
    _queued.clear();
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
    final removable = unreferencedAttachments(
      candidates: attachments,
      conversations: _conversations,
      thread: _messages,
      pending: _pendingAttachments,
      queued: _queued.map((outgoing) => outgoing.attachments),
    );
    if (removable.isEmpty) {
      return;
    }
    unawaited(ref.read(attachmentStoreProvider).delete(removable));
  }

  Future<void> _newChat() async {
    _abandonGeneration();
    _dropQueue();
    _stopSpeaking();
    _forgetEdit();
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
    _abandonGeneration();
    _dropQueue();
    _stopSpeaking();
    _forgetEdit();
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

  // ---- actions d'un message ------------------------------------------------

  void _copyMessage(ChatMessage message) {
    Clipboard.setData(ClipboardData(text: message.content));
    _showSnack('Réponse copiée.');
  }

  Future<void> _shareMessage(ChatMessage message) async {
    if (message.content.trim().isEmpty) {
      return;
    }
    try {
      await SharePlus.instance.share(ShareParams(text: message.content));
    } catch (_) {
      _showSnack('Partage impossible depuis cet appareil.');
    }
  }

  /// Note une réponse, ou retire la note si on appuie deux fois.
  ///
  /// L'avis reste sur l'appareil : FoxLLM n'a pas de serveur à qui
  /// l'envoyer, et n'en aura pas. C'est un repère pour retrouver une bonne
  /// réponse dans un long fil, pas un retour transmis à quiconque.
  void _rateMessage(int index, MessageRating rating) {
    if (index < 0 || index >= _messages.length) {
      return;
    }
    final current = _messages[index];
    setState(() {
      _messages[index] = current.copyWith(
        rating: current.rating == rating ? MessageRating.none : rating,
      );
      _syncActiveConversation();
    });
  }

  Future<void> _speakMessage(ChatMessage message) async {
    // Type explicite : sans lui, `??=` rend une référence nullable et chaque
    // appel derrière réclamerait un `!`.
    final Speech speech = _speech ?? ref.read(speechProvider);
    if (_speech == null) {
      _speech = speech;
      // Le service est la seule source de vérité. La lecture s'achève d'elle
      // même à la fin du texte, sans que personne n'appelle `stop()` : sans
      // cette écoute, le bouton resterait allumé après la dernière syllabe,
      // et le rappuyer relancerait la lecture au lieu de l'arrêter.
      speech.speaking.addListener(_onSpeakingChanged);
    }
    // Le moteur vocal n'est monté qu'ici : c'est `speaking` qui préviendra,
    // au démarrage comme à la fin.
    await speech.toggle(message.content);
  }

  void _onSpeakingChanged() {
    if (!mounted) {
      return;
    }
    setState(() => _speakingText = _speech?.speaking.value);
  }

  /// Rejoue la demande qui a produit [index], en remplaçant la réponse.
  Future<void> _regenerate(int index) async {
    final userIndex = index - 1;
    if (userIndex < 0 || _messages[userIndex].role != ChatRole.user) {
      return;
    }
    final question = _messages[userIndex];
    await _resendFrom(userIndex, question.content, question.attachments);
  }

  /// Repart du message utilisateur [userIndex], que la suite du fil soit
  /// devenue obsolète parce qu'il a été modifié ou parce qu'on rejoue.
  Future<void> _resendFrom(
    int userIndex,
    String text,
    List<ChatAttachment> attachments,
  ) async {
    if (_isGenerating || _sending) {
      _showSnack('Attends la fin de la réponse en cours.');
      return;
    }
    // Rien n'est retiré ici. La coupe voyage avec l'envoi et n'a lieu qu'une
    // fois celui-ci validé : tronquer d'abord amputait définitivement la
    // conversation quand l'envoi était ensuite refusé, faute de modèle chargé
    // par exemple, sans même que la demande parte.
    //
    // Les pièces jointes repartent avec le message plutôt que par le
    // brouillon : leurs fichiers sont encore là, et le brouillon en cours
    // d'écriture ne doit pas être touché.
    await _startSend(
      _Outgoing(
        text: text.trim(),
        attachments: List<ChatAttachment>.of(attachments),
        conversationId: _activeConversationId,
        replaceFrom: userIndex,
      ),
    );
  }

  /// Rattache à la dernière réponse les sources relevées par le moteur.
  ///
  /// Le contrat des moteurs ne transporte que du texte : les citations sont
  /// relevées de côté pendant le flux, puis reprises ici pour être
  /// conservées avec le message.
  void _attachCitations(LocalLlmBackend backend) {
    if (backend is! PersonalApiChatBackend) {
      return;
    }
    final citations = backend.citations;
    if (citations.isEmpty || _messages.isEmpty) {
      return;
    }
    final last = _messages.length - 1;
    if (_messages[last].role != ChatRole.assistant) {
      return;
    }
    setState(() {
      _messages[last] = _messages[last].copyWith(
        citations: List<Citation>.of(citations),
      );
      _syncActiveConversation();
    });
  }

  /// Note la vitesse d'écriture d'une réponse produite sur l'appareil.
  ///
  /// Seul le moteur local la mesure, et `PersonalApiChatBackend` renvoie
  /// toujours vers le fournisseur distant : c'est donc l'absence de celui-ci
  /// qui dit qu'on vient de générer ici. Sans ce contrôle, une réponse
  /// distante hériterait de la vitesse de la dernière génération locale,
  /// mesurée pour un tout autre modèle.
  Future<void> _attachGenerationSpeed(
    LocalLlmBackend backend,
    int generationEpoch,
    int? conversationId,
  ) async {
    if (backend is PersonalApiChatBackend) {
      return;
    }

    final stats = await backend.lastGenerationStats;
    if (stats == null ||
        stats.generatedTokens <= 0 ||
        stats.tokensPerSecond <= 0) {
      return;
    }
    // La lecture est asynchrone : le fil a pu changer entre-temps, et la
    // vitesse n'appartiendrait plus à ce qui est à l'écran.
    if (!_isCurrentThread(generationEpoch, conversationId) ||
        _messages.isEmpty ||
        _messages.last.role != ChatRole.assistant) {
      return;
    }

    setState(() {
      _messages[_messages.length - 1] = _messages.last.copyWith(
        generationSpeed: stats.tokensPerSecond,
      );
      _syncActiveConversation();
    });
  }

  /// Liste les pages consultées par le modèle pour cette réponse.
  void _showSources(ChatMessage message) {
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
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                message.citations.length == 1
                    ? '1 source'
                    : '${message.citations.length} sources',
                style: TextStyle(
                  color: fox.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: message.citations.length,
                  itemBuilder: (context, index) {
                    final citation = message.citations[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(
                        citation.label,
                        style: TextStyle(color: fox.textPrimary, fontSize: 15),
                      ),
                      subtitle: Text(
                        citation.host,
                        style: TextStyle(color: fox.textTertiary, fontSize: 13),
                      ),
                      trailing: Icon(
                        Icons.open_in_new_rounded,
                        size: 18,
                        color: fox.textTertiary,
                      ),
                      onTap: () => unawaited(_openCitation(citation)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCitation(Citation citation) async {
    final uri = Uri.tryParse(citation.url);
    // `openExternalLink` refuse déjà tout ce qui n'est pas http ou https :
    // une adresse citée par un modèle reste du texte non vérifié.
    if (uri == null || !await openExternalLink(uri)) {
      if (mounted) {
        _showSnack('Impossible d’ouvrir cette source.');
      }
    }
  }

  // ---- modification d'un message utilisateur -------------------------------

  void _startEdit(int index) {
    if (index < 0 || index >= _messages.length) {
      return;
    }
    _editController.text = _messages[index].content;
    setState(() {
      _editingIndex = index;
      _editingConversationId = _activeConversationId;
      _editingOriginal = _messages[index].content;
    });
  }

  void _cancelEdit() {
    setState(_forgetEdit);
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// Oublie la modification en cours, sans reconstruire l'écran.
  ///
  /// À appeler dès qu'on quitte le fil édité : la modification n'a plus de
  /// message à désigner, et son texte ne doit pas se reporter ailleurs.
  void _forgetEdit() {
    _editingIndex = null;
    _editingConversationId = null;
    _editingOriginal = null;
    _editController.clear();
  }

  Future<void> _submitEdit() async {
    final index = _editingIndex;
    // L'édition ne vaut que pour le fil et le message où elle a commencé.
    // L'écran a pu changer entre-temps : autre conversation, fil rejoué,
    // message supprimé. Dans tous ces cas, la validation est abandonnée
    // plutôt qu'appliquée à un message qui n'est pas celui qu'on modifiait.
    if (index == null ||
        _editingConversationId != _activeConversationId ||
        index >= _messages.length ||
        _messages[index].role != ChatRole.user ||
        _messages[index].content != _editingOriginal) {
      setState(_forgetEdit);
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    final text = _editController.text.trim();
    final attachments = List<ChatAttachment>.of(_messages[index].attachments);
    if (text.isEmpty && attachments.isEmpty) {
      return;
    }
    setState(_forgetEdit);
    FocusManager.instance.primaryFocus?.unfocus();
    await _resendFrom(index, text, attachments);
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    final attachments = List<ChatAttachment>.of(_pendingAttachments);
    if (text.isEmpty && attachments.isEmpty) {
      return;
    }

    if (_isGenerating || _sending) {
      // Une réponse est en cours : le message prend la file plutôt que de
      // disparaître ou d'interrompre ce qui s'écrit. Ses pièces jointes
      // partent avec lui, elles ne restent pas dans le brouillon.
      //
      // Il ne vient plus du composeur une fois mis en attente : le brouillon
      // est vidé ici, et celui qu'on écrira d'ici son départ appartient à
      // l'utilisateur.
      setState(() {
        _queued.add(
          _Outgoing(
            text: text,
            attachments: attachments,
            conversationId: _activeConversationId,
          ),
        );
        _inputController.clear();
        _pendingAttachments.clear();
      });
      return;
    }

    await _startSend(
      _Outgoing(
        text: text,
        attachments: attachments,
        conversationId: _activeConversationId,
        fromComposer: true,
      ),
    );
  }

  /// Envoie le premier message en attente, si la voie est libre.
  ///
  /// Un seul par appel : l'envoi déclenché ici rappellera cette méthode à son
  /// tour, ce qui vide la file dans l'ordre sans boucle d'attente.
  Future<void> _drainQueue() async {
    if (!mounted || _queued.isEmpty || _isGenerating || _sending) {
      return;
    }
    // Le message quitte la file le temps de son envoi, puis y revient en tête
    // s'il est refusé : une préparation impossible, faute de modèle par
    // exemple, ne doit pas le perdre. Le retirer après coup ne marcherait pas,
    // l'envoi relançant lui-même le défilement avant de rendre la main.
    //
    // Un refus n'est pas réessayé tout seul : le défilement s'arrête là,
    // plutôt que de vider la file en boucle sur la même erreur.
    final queueEpoch = _queueEpoch;
    final next = _queued.removeAt(0);
    final sent = await _startSend(next);
    if (!sent && mounted && queueEpoch == _queueEpoch) {
      setState(() => _queued.insert(0, next));
    }
  }

  /// Ramène un message en attente dans le composeur, pour le corriger.
  ///
  /// Le brouillon en cours prend sa place dans la file plutôt que d'être
  /// écrasé : l'échange ne perd ni l'un ni l'autre, pièces jointes comprises.
  void _resumeQueued(_Outgoing message) {
    final index = _queued.indexOf(message);
    if (index < 0) {
      return;
    }
    final draft = _Outgoing(
      text: _inputController.text.trim(),
      attachments: List<ChatAttachment>.of(_pendingAttachments),
      conversationId: _activeConversationId,
    );
    setState(() {
      if (draft.isEmpty) {
        _queued.removeAt(index);
      } else {
        _queued[index] = draft;
      }
      _inputController.text = message.text;
      _inputController.selection = TextSelection.collapsed(
        offset: message.text.length,
      );
      _pendingAttachments
        ..clear()
        ..addAll(message.attachments);
    });
  }

  /// Donne au fil qui vient de naître les messages qui l'attendaient.
  ///
  /// Appelé depuis le `setState` de validation : la file est modifiée en
  /// place, sans nouvelle reconstruction.
  void _adoptQueuedIntoNewThread(int id) {
    for (var i = 0; i < _queued.length; i++) {
      if (_queued[i].conversationId == null) {
        _queued[i] = _queued[i].withConversation(id);
      }
    }
  }

  /// Retire un message de la file, définitivement.
  void _removeQueued(_Outgoing message) {
    if (!_queued.remove(message)) {
      return;
    }
    setState(() {});
    _deleteUnreferencedAttachments(message.attachments);
  }

  /// Lance [outgoing]. Rend `true` seulement s'il a rejoint le fil.
  ///
  /// La valeur rendue est ce qui permet à la file de ne retirer un message
  /// qu'une fois parti : un refus le laisse là où il est.
  Future<bool> _startSend(_Outgoing outgoing) async {
    // `_isGenerating` n'est levé qu'une fois la requête partie : sans ce
    // second verrou, deux appuis rapprochés pendant l'ouverture du modèle ou
    // la lecture des réglages lanceraient deux envois, dont un serait perdu.
    if (outgoing.isEmpty || _isGenerating || _sending) {
      return false;
    }
    // Le verrou est posé avant la moindre attente : pendant la relecture, un
    // second appui doit rejoindre la file plutôt que lancer un envoi parallèle.
    //
    // Posé dans un `setState` : l'écran s'en sert pour éteindre les actions
    // qui n'ont pas de sens pendant une préparation, comme le rétablissement
    // d'une version précédente.
    setState(() => _sending = true);
    var outcome = _SendOutcome.refused;
    try {
      // La relecture remplace la liste des conversations : écrire dedans
      // avant son retour ferait disparaître ce message à son arrivée.
      await _historyRestored.future;
      if (!mounted) {
        return false;
      }
      outcome = await _send(outgoing);
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      } else {
        _sending = false;
      }
    }
    // La file repart une fois la voie libre, jamais depuis le `finally` : le
    // verrou d'envoi y est encore posé. Un envoi refusé arrête le défilement
    // plutôt que de le relancer en boucle, et une réponse en échec ne doit pas
    // l'enchaîner comme si elle avait abouti.
    if (outcome == _SendOutcome.sent) {
      await _drainQueue();
    }
    return outcome != _SendOutcome.refused;
  }

  /// Prépare, valide, puis seulement alors modifie le fil.
  ///
  /// Rend `true` si le message a rejoint la conversation. Tout ce qui peut
  /// refuser l'envoi (modèle absent, mode incompatible, pièce jointe refusée,
  /// changement de fil) est vérifié avant la moindre mutation : une
  /// régénération refusée tronquait sinon la conversation pour rien.
  /// Réunit tout ce qu'un envoi doit avoir avant de partir, ou rend `null`.
  ///
  /// Cette phase n'écrit rien dans le fil : elle ouvre le modèle s'il le
  /// faut, compose l'historique, refuse ce qui ne peut pas aboutir, et lit le
  /// contenu des pièces jointes. Chaque refus a déjà été expliqué à
  /// l'utilisateur quand elle rend `null`.
  ///
  /// Elle dure : un modèle local met plusieurs secondes à s'ouvrir, une pièce
  /// jointe à se lire. L'identité de l'envoi est donc revérifiée à chaque
  /// reprise, car l'utilisateur a pu changer de fil entre-temps.
  ///
  /// Séparée de l'envoi lui-même parce qu'elle n'a rien de commun avec lui :
  /// ici rien n'est encore engagé, et tout peut être abandonné sans laisser
  /// de trace. Passé ce point, le fil est modifié et chaque sortie doit le
  /// remettre d'aplomb.
  Future<_PreparedSend?> _prepareSend(
    _Outgoing outgoing, {
    required LocalLlmBackend backend,
    required int generationEpoch,
    required int? conversationId,
  }) async {
    final text = outgoing.text;
    if (backend.loadedModelPath == null) {
      // Le modèle de la session précédente n'est ouvert qu'ici, pour ne pas
      // retarder l'affichage du chat au lancement.
      final restorable = _restorableModelPath;
      if (restorable == null) {
        _showModelRequired();
        return null;
      }
      if (!await _restoreModel(backend, restorable)) {
        return null;
      }
      if (!_isCurrentThread(generationEpoch, conversationId)) {
        // Fil abandonné pendant le chargement. Le brouillon de celui qui est
        // à l'écran maintenant appartient à l'utilisateur : on n'y touche pas.
        return null;
      }
    }

    final attachments = outgoing.attachments;
    // La coupe d'une régénération ou d'une modification se calcule ici, sans
    // toucher au fil : rien n'est retiré tant que l'envoi n'est pas validé.
    final kept = outgoing.replaceFrom == null
        ? _messages
        : _messages.take(outgoing.replaceFrom!);
    final history = <ChatMessage>[
      ...kept,
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
        'La recherche web demande une API personnelle Anthropic, Google ou '
        'OpenAI. '
        'Désactive-la ou change de fournisseur.',
      );
      return null;
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
      return null;
    }
    if (!_isCurrentThread(generationEpoch, conversationId)) {
      return null;
    }

    return _PreparedSend(
      history: history,
      requestMessages: requestMessages,
      modes: modes,
    );
  }

  /// Inscrit au fil ce qu'une génération terminée y laisse, et rend son issue.
  ///
  /// Appelée seulement quand le fil visé est toujours celui qui est ouvert :
  /// ce qui suit touche à ce que l'utilisateur regarde.
  ///
  /// Le mot « terminée » n'engage rien sur la réussite : un flux arrêté ou
  /// écourté passe aussi par ici, et c'est justement l'issue rendue qui le
  /// dira.
  GenerationOutcome _settleFinishedGeneration(
    LocalLlmBackend backend, {
    required String response,
    required List<ChatMessage>? replaced,
    required int generationEpoch,
    required int? conversationId,
  }) {
    if (response.isNotEmpty) {
      _attachCitations(backend);
      unawaited(
        _attachGenerationSpeed(backend, generationEpoch, conversationId),
      );
    }

    // Lue même sans un mot reçu : un flux qui s'annonce écourté avant le
    // premier fragment reste écourté, et le traiter comme une réussite
    // faisait disparaître la bulle sans rien dire.
    final outcome = _recordOutcome(backend, generationEpoch);
    if (response.isEmpty && outcome == GenerationOutcome.complete) {
      // Une réponse vide et pourtant aboutie n'a rien à montrer.
      _removeEmptyAssistantPlaceholder();
    }
    if (replaced != null) {
      // Un remplacement abouti rend caduque la version d'avant ; un
      // remplacement écourté ou arrêté la garde reprenable, sans limite de
      // temps.
      _keepPreviousVersion(
        outcome == GenerationOutcome.complete ? null : replaced,
        generationEpoch,
        conversationId,
      );
    }
    return outcome;
  }

  /// Remet le fil d'aplomb après une génération interrompue, et dit pourquoi.
  ///
  /// Quatre situations, et quatre issues différentes. Le fil peut porter ou
  /// non du texte reçu avant la coupure ; l'envoi peut remplacer ou non une
  /// version précédente. Rien n'est jeté dans aucune d'elles : le texte reçu
  /// reste affiché parce que c'est ce que l'utilisateur a vu, et la version
  /// remplacée reste reprenable parce qu'elle est la seule trace de ce qui a
  /// été effacé.
  ///
  /// Appelée seulement quand le fil visé est encore celui qui est ouvert.
  /// Rend l'issue à retenir pour la réponse affichée.
  GenerationOutcome _recoverFromFailure(
    Object error, {
    required String response,
    required List<ChatMessage>? replaced,
    required int generationEpoch,
    required int? conversationId,
    required GenerationOutcome outcome,
  }) {
    var settled = outcome;
    if (response.isNotEmpty) {
      // Le texte reçu reste à l'écran, c'est ce que l'utilisateur a vu, mais
      // il ne doit pas passer pour une réponse entière.
      _markLastAssistantOutcome(GenerationOutcome.failed, null);
      settled = GenerationOutcome.failed;
    }

    if (replaced == null) {
      if (response.isEmpty) {
        // Rien n'est arrivé : seule la bulle restée vide s'en va.
        _removeEmptyAssistantPlaceholder();
      }
      _showSnack('Génération impossible : ${_describeError(error)}');
    } else if (response.isEmpty) {
      // Rien n'est arrivé du moteur : le remplacement n'a pas eu lieu. Le fil
      // revient tel qu'il était, réponse effacée comprise, plutôt que de
      // rester amputé de tout ce qui suivait la question.
      _restoreThread(replaced, generationEpoch, conversationId);
      _showSnack(
        'Génération impossible : ${_describeError(error)}. '
        'Réponse précédente conservée.',
      );
    } else {
      // Du texte est arrivé avant la coupure : il reste affiché, et la
      // version qu'il a remplacée est conservée avec la conversation. Les
      // deux survivent donc à la navigation et au redémarrage, là où une
      // action de bandeau disparaissait au bout de quelques secondes.
      _keepPreviousVersion(replaced, generationEpoch, conversationId);
      _showSnack(
        'Génération interrompue : ${_describeError(error)}. '
        'Version précédente conservée.',
      );
    }
    return settled;
  }

  /// Engage l'envoi dans le fil : à partir d'ici, l'écran est modifié.
  ///
  /// Tout ce qui précède pouvait être abandonné sans laisser de trace. Ce
  /// n'est plus vrai après : la question est posée, la bulle de réponse est
  /// ouverte, et chaque sortie devra remettre le fil d'aplomb.
  ///
  /// Rend l'identité du fil, qui vient peut-être d'être créé par ce message,
  /// et la version qu'un remplacement efface.
  _CommittedSend _commitOutgoing(
    _Outgoing outgoing, {
    required List<ChatMessage> history,
    required int generationEpoch,
  }) {
    // La lecture d'un message sur le point de disparaître s'arrête.
    if (outgoing.replaceFrom case final from?) {
      final speaking = _speech?.speaking.value;
      if (speaking != null &&
          _messages
              .skip(from)
              .any((message) => message.content.trim() == speaking)) {
        _stopSpeaking();
      }
    }

    // Version d'avant le remplacement, copiée juste avant la mutation. Une
    // régénération ou une modification coupe la fin du fil : si la génération
    // échoue, c'est la seule trace qui reste de la réponse effacée, de ses
    // pièces jointes et de ses citations.
    final replaced = outgoing.replaceFrom == null
        ? null
        : List<ChatMessage>.of(_messages);

    late final int? conversationId;
    setState(() {
      _ensureActiveConversation(outgoing.text);
      conversationId = _activeConversationId;
      // Ce fil appartient désormais à cette génération : une opération plus
      // ancienne qui reviendrait plus tard n'a plus rien à y faire.
      _lastGeneration[conversationId!] = generationEpoch;
      if (outgoing.conversationId == null) {
        // Ce premier message vient de créer le fil. Ceux mis en attente
        // pendant sa préparation visaient ce même fil, qui n'avait pas encore
        // d'identifiant : ils le reçoivent maintenant, au lieu d'être refusés
        // pour une identité qu'ils ne pouvaient pas connaître.
        _adoptQueuedIntoNewThread(conversationId!);
      }
      _messages
        ..clear()
        ..addAll(history)
        ..add(const ChatMessage.assistant(''));
      _isGenerating = true;
      _syncActiveConversation();
    });

    if (outgoing.fromComposer && _draftStillMatches(outgoing)) {
      // Le brouillon n'est vidé qu'une fois le message parti, et seulement
      // s'il porte encore ce qui est parti : la préparation dure parfois
      // plusieurs secondes, pendant lesquelles l'utilisateur écrit la suite.
      setState(() {
        _inputController.clear();
        _pendingAttachments.clear();
      });
    }
    _scrollToBottom();

    return _CommittedSend(conversationId: conversationId, replaced: replaced);
  }

  Future<_SendOutcome> _send(_Outgoing outgoing) async {
    final backend = ref.read(chatBackendProvider);

    // Identité de cet envoi, prise avant la moindre attente. Le chargement du
    // modèle prend plusieurs secondes, pendant lesquelles l'utilisateur peut
    // ouvrir un autre fil ou en créer un : l'envoi reprenait alors avec
    // l'ancien texte et le nouvel historique.
    final generationEpoch = ++_generationEpoch;
    // Le fil visé est celui d'où l'envoi est parti, pas celui affiché au
    // moment d'aboutir.
    var conversationId = outgoing.conversationId;
    // `null` désigne le fil qui reste à créer, jamais « n'importe lequel » :
    // il n'est accepté que tant qu'aucun fil n'est ouvert. Les messages mis
    // en attente pendant cette création sont rattachés plus bas, dès que le
    // fil a une identité.
    if (conversationId != _activeConversationId) {
      return _SendOutcome.refused;
    }
    bool stillCurrent() => _isCurrentThread(generationEpoch, conversationId);

    final prepared = await _prepareSend(
      outgoing,
      backend: backend,
      generationEpoch: generationEpoch,
      conversationId: conversationId,
    );
    if (prepared == null) {
      return _SendOutcome.refused;
    }
    final history = prepared.history;
    final requestMessages = prepared.requestMessages;
    final modes = prepared.modes;

    final committed = _commitOutgoing(
      outgoing,
      history: history,
      generationEpoch: generationEpoch,
    );
    // Le fil vient peut-être de naître : l'envoi suit désormais son identité,
    // et `stillCurrent` avec lui, puisqu'il la referme.
    conversationId = committed.conversationId;
    final replaced = committed.replaced;

    var response = '';
    var failed = false;
    var outcome = GenerationOutcome.complete;
    // Ce qu'est devenue la génération, vu du fil qu'on a peut-être quitté.
    // Par défaut une interruption : quitter un fil en cours de réponse
    // l'interrompt, même si le moteur, lui, va au bout.
    var abandonedOutcome = GenerationOutcome.cancelled;

    // `clock.now()` plutôt que `Stopwatch` : l'un comme l'autre donnent
    // l'heure réelle sur un appareil, mais seul le premier suit l'horloge
    // simulée des tests, qui vérifient l'affichage fragment par fragment.
    var lastPaint = clock.now();
    var shown = '';

    // Pousse à l'écran ce que le groupement retient encore.
    //
    // Appelée à chaque sortie de la boucle, la fin normale comme l'échec : un
    // flux qui casse après un fragment retenu perdrait sinon ce fragment,
    // alors que c'est précisément ce que la gestion d'erreur s'attache à
    // garder affiché.
    void flushDisplay() {
      if (shown == response || !stillCurrent()) {
        return;
      }
      shown = response;
      setState(() {
        _messages[_messages.length - 1] = ChatMessage.assistant(response);
        _syncActiveConversation(immediate: false);
      });
      _scrollToBottom();
    }

    try {
      final settings = GenerationSettings(
        maxTokens: modes.reasoning
            ? reasoningMaxTokens
            : const GenerationSettings().maxTokens,
        webSearch: modes.webSearch,
      );
      // Afficher un message coûte cher : le markdown est ré-analysé et le
      // code recoloré à chaque image, pour tous les messages visibles.
      // Repeindre à chaque fragment reçu faisait donc croître le travail avec
      // le carré de la longueur de la réponse, sur le fil principal, et au
      // moment précis où l'appareil est déjà occupé à produire la suite.
      //
      // Les fragments sont donc groupés. `shown` retient ce qui est affiché :
      // une comparaison avec le texte reçu vaut mieux qu'un drapeau, car elle
      // reste juste quelle que soit la façon dont la boucle s'est terminée.

      await for (final chunk in backend.generate(
        messages: requestMessages,
        settings: settings,
      )) {
        response += chunk;
        if (!stillCurrent()) {
          // Le message a bien rejoint son fil : seule la suite est abandonnée.
          return _SendOutcome.sent;
        }
        final now = clock.now();
        if (now.difference(lastPaint) < _streamPaintInterval) {
          continue;
        }
        lastPaint = now;
        shown = response;
        setState(() {
          _messages[_messages.length - 1] = ChatMessage.assistant(response);
          // Un état intermédiaire que personne ne relira : il rejoint le
          // prochain enregistrement groupé plutôt que d'en déclencher un.
          _syncActiveConversation(immediate: false);
        });
        _scrollToBottom();
      }

      // Le flux est fini : plus rien ne viendra pousser à l'écran ce que le
      // groupement retenait.
      flushDisplay();

      // Le flux s'est terminé, que le fil soit encore à l'écran ou non. Un
      // arrêt demandé, par le bouton comme par une navigation, l'a peut-être
      // provoqué : c'est une interruption, pas une réponse achevée.
      abandonedOutcome = _cancelledEpoch == generationEpoch
          ? GenerationOutcome.cancelled
          : _incompleteReasonOf(backend) == null
          ? GenerationOutcome.complete
          : GenerationOutcome.incomplete;

      if (stillCurrent()) {
        outcome = _settleFinishedGeneration(
          backend,
          response: response,
          replaced: replaced,
          generationEpoch: generationEpoch,
          conversationId: conversationId,
        );
      }
    } catch (error) {
      // Avant toute chose : ce qui est arrivé avant la coupure doit être
      // visible, c'est sur lui que repose toute la suite.
      flushDisplay();
      if (!stillCurrent()) {
        // Le fil n'est plus à l'écran : l'échec est noté pour lui, là où il
        // vit, plutôt que montré sur une conversation qui n'a rien demandé.
        abandonedOutcome = GenerationOutcome.failed;
        return _SendOutcome.sent;
      }
      outcome = _recoverFromFailure(
        error,
        response: response,
        replaced: replaced,
        generationEpoch: generationEpoch,
        conversationId: conversationId,
        outcome: outcome,
      );
      failed = true;
    } finally {
      if (stillCurrent()) {
        setState(() {
          _isGenerating = false;
          _syncActiveConversation();
        });
      } else {
        // Le fil visé n'est plus celui qui est ouvert : on n'y touche pas,
        // mais celui qu'on a quitté doit garder ce qui est arrivé, et la
        // version que le remplacement venait d'effacer.
        _settleAbandonedThread(
          conversationId: conversationId,
          generationEpoch: generationEpoch,
          response: response,
          replaced: replaced,
          outcome: abandonedOutcome,
        );
      }
    }
    if (failed) {
      return _SendOutcome.failed;
    }
    // Une réponse écourtée n'enchaîne pas la file : il n'y a rien d'automatique
    // à faire d'une réponse dont on sait qu'elle n'est pas allée au bout.
    return outcome == GenerationOutcome.incomplete
        ? _SendOutcome.incomplete
        : _SendOutcome.sent;
  }

  /// Note sur la réponse ce qui y a mis fin, et le rend.
  ///
  /// Lu à la toute fin du flux : le moteur remet son état à zéro au début de
  /// chaque génération, donc ce qui est lu ici appartient bien à celle-ci.
  GenerationOutcome _recordOutcome(LocalLlmBackend backend, int epoch) {
    if (_cancelledEpoch == epoch) {
      _markLastAssistantOutcome(GenerationOutcome.cancelled, null);
      return GenerationOutcome.cancelled;
    }
    final reason = _incompleteReasonOf(backend);
    if (reason == null) {
      return GenerationOutcome.complete;
    }
    _markLastAssistantOutcome(GenerationOutcome.incomplete, reason);
    return GenerationOutcome.incomplete;
  }

  /// Motif d'une réponse écourtée rapporté par le moteur, ou `null`.
  ///
  /// Filtré par le type, et non par le nom du fournisseur : le chat n'a pas à
  /// connaître celui qui parle.
  String? _incompleteReasonOf(LocalLlmBackend backend) => switch (backend) {
    final IncompleteAwareBackend aware => aware.incompleteReason,
    _ => null,
  };

  /// Marque la dernière réponse du fil, à l'écran comme à l'enregistrement.
  void _markLastAssistantOutcome(GenerationOutcome outcome, String? reason) {
    if (_messages.isEmpty || _messages.last.role != ChatRole.assistant) {
      return;
    }
    setState(() {
      _messages[_messages.length - 1] = _messages.last.copyWith(
        outcome: outcome,
        outcomeReason: reason,
      );
      _syncActiveConversation();
    });
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
    _enforceConversationLimit();
  }

  /// Écarte les conversations que l'historique ne peut plus porter.
  ///
  /// `ConversationStore` n'enregistre que les [ConversationStore.maxConversations]
  /// premières. Sans ce ménage, les suivantes restaient à l'écran jusqu'à la
  /// fermeture puis disparaissaient au lancement suivant, en laissant leurs
  /// pièces jointes sur le disque : une perte silencieuse, et des fichiers
  /// que plus rien ne citait.
  ///
  /// La liste est rangée de la plus récente à la plus ancienne : ce sont donc
  /// bien les plus anciennes qui partent, et jamais celle qui est ouverte.
  void _enforceConversationLimit() {
    final dropped = conversationsBeyondLimit(
      conversations: _conversations,
      activeConversationId: _activeConversationId,
      limit: ConversationStore.maxConversations,
    );
    if (dropped.isEmpty) {
      return;
    }

    _conversations.removeWhere(dropped.contains);
    unawaited(
      ref
          .read(attachmentStoreProvider)
          .delete(dropped.expand((conversation) => conversation.attachments)),
    );
  }

  /// Titre de la barre du haut : celui du fil ouvert, sinon le nom de l'app.
  ///
  /// Le fil n'existe qu'à partir du premier message : avant, il n'y a aucun
  /// titre à donner, et inventer un « Nouvelle conversation » n'apprendrait
  /// rien de plus que l'écran déjà vide.
  String get _topBarTitle {
    final id = _activeConversationId;
    final conversation = id == null ? null : _conversationById(id);
    return conversation?.title ?? 'FoxLLM';
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
    // L'arrêt appartient à la génération en cours : sans ce repère, la fin de
    // flux qu'il provoque ressemblait à une réponse allée au bout.
    _cancelledEpoch = _generationEpoch;
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

  /// Met un échec de génération en français.
  ///
  /// Interpolé tel quel, un échec HTTP versait le corps entier de la réponse
  /// dans le bandeau : une page d'erreur de proxy, un pavé JSON. La
  /// traduction existait déjà pour l'écran des réglages, elle vaut autant
  /// ici, où l'utilisateur la lit bien plus souvent.
  String _describeError(Object error) => describePersonalApiError(error);

  void _showSnack(String message, {SnackBarAction? action}) {
    // Un échec tardif, revenu après la fermeture de l'écran, n'a plus de
    // `context` où afficher quoi que ce soit : le message est abandonné
    // plutôt que de lever une exception par-dessus l'erreur d'origine.
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: action,
          // Le temps de lire l'erreur et d'atteindre le bouton.
          duration: action == null
              ? const Duration(seconds: 4)
              : const Duration(seconds: 10),
        ),
      );
  }

  /// Vrai si le composeur porte encore exactement ce qui est parti.
  ///
  /// Le texte et les pièces jointes d'un envoi sont figés avant la
  /// préparation, qui peut durer plusieurs secondes. Vider le composeur sans
  /// regarder effaçait le message écrit pendant ce temps.
  bool _draftStillMatches(_Outgoing outgoing) {
    if (_inputController.text.trim() != outgoing.text) {
      return false;
    }
    if (_pendingAttachments.length != outgoing.attachments.length) {
      return false;
    }
    for (var index = 0; index < _pendingAttachments.length; index++) {
      if (_pendingAttachments[index].path != outgoing.attachments[index].path) {
        return false;
      }
    }
    return true;
  }

  /// Vrai tant que [generationEpoch] désigne l'opération en cours.
  ///
  /// C'est la règle de ce qui écrit dans une conversation **par son
  /// identifiant** : une conversation quittée reste modifiable, et c'est même
  /// tout l'intérêt, puisqu'une génération abandonnée doit y déposer ce
  /// qu'elle a produit.
  bool _isCurrentGeneration(int generationEpoch) =>
      mounted && generationEpoch == _generationEpoch;

  /// Vrai si [generationEpoch] est en cours **et** que [conversationId] est le
  /// fil affiché.
  ///
  /// C'est la règle, plus stricte, de tout ce qui touche à `_messages` : une
  /// génération abandonnée, ou un bouton pressé après avoir changé de fil, ne
  /// doit jamais réécrire ce qui est ouvert maintenant.
  ///
  /// Les deux règles se ressemblent assez pour qu'on prenne l'une pour
  /// l'autre. Les nommer est ce qui rend le choix visible à la lecture, là où
  /// quatre copies écrites à la main le laissaient deviner.
  bool _isCurrentThread(int generationEpoch, int? conversationId) =>
      _isCurrentGeneration(generationEpoch) &&
      conversationId == _activeConversationId;

  /// Conserve avec la conversation la version d'avant un remplacement.
  ///
  /// Enregistrée, donc reprenable après une navigation ou un redémarrage. La
  /// version obtenue, même partielle, reste affichée : aucune des deux n'est
  /// jetée.
  /// [previous] à `null` oublie celle qui était conservée.
  void _keepPreviousVersion(
    List<ChatMessage>? previous,
    int generationEpoch,
    int? conversationId,
  ) {
    if (!_isCurrentGeneration(generationEpoch)) {
      return;
    }
    final conversation = conversationId == null
        ? null
        : _conversationById(conversationId);
    if (conversation == null) {
      return;
    }
    final dropped = conversation.previousMessages;
    if (dropped == null && previous == null) {
      return;
    }
    setState(() {
      conversation.previousMessages = previous == null
          ? null
          : List<ChatMessage>.unmodifiable(previous);
      _persistConversations();
    });
    if (dropped != null) {
      _deleteUnreferencedAttachments(<ChatAttachment>[
        for (final message in dropped) ...message.attachments,
      ]);
    }
  }

  /// Version conservée du fil ouvert, ou `null` s'il n'y a rien à reprendre.
  List<ChatMessage>? get _previousVersion {
    final id = _activeConversationId;
    return id == null ? null : _conversationById(id)?.previousMessages;
  }

  /// Vrai tant qu'un envoi se prépare ou qu'une réponse s'écrit.
  ///
  /// Le fil appartient alors à cette opération : le remplacer sous ses pieds
  /// laisserait le fragment suivant écrire par-dessus la version rétablie.
  bool get _operationInFlight => _sending || _isGenerating;

  /// Échange la version affichée et la version conservée.
  ///
  /// Un échange, et non un remplacement : celle qu'on quitte prend la place
  /// de celle qu'on reprend, donc rien ne disparaît et le geste se refait
  /// dans l'autre sens.
  void _swapWithPreviousVersion() {
    // Le garde ne tient pas qu'au bouton : une action déclenchée juste avant
    // le départ d'un envoi ne doit pas passer non plus.
    if (_operationInFlight) {
      return;
    }
    final id = _activeConversationId;
    if (id == null) {
      return;
    }
    final conversation = _conversationById(id);
    final previous = conversation?.previousMessages;
    if (conversation == null || previous == null) {
      return;
    }
    final current = List<ChatMessage>.unmodifiable(_messages);
    setState(() {
      _messages
        ..clear()
        ..addAll(previous);
      _syncActiveConversation();
      conversation.previousMessages = current;
      _persistConversations();
    });
  }

  /// Oublie la version conservée, à la demande.
  ///
  /// Refusé pendant une opération pour la même raison que l'échange : elle
  /// efface les copies des pièces jointes que cette version cite, or un envoi
  /// en cours peut encore avoir à la rétablir.
  void _forgetPreviousVersion() {
    if (_operationInFlight) {
      return;
    }
    final id = _activeConversationId;
    final conversation = id == null ? null : _conversationById(id);
    final previous = conversation?.previousMessages;
    if (conversation == null || previous == null) {
      return;
    }
    setState(() {
      conversation.previousMessages = null;
      _persistConversations();
    });
    _deleteUnreferencedAttachments(<ChatAttachment>[
      for (final message in previous) ...message.attachments,
    ]);
  }

  /// Rend au fil la version d'avant un remplacement.
  ///
  /// Encadrée par l'identité de l'opération et de la conversation : une
  /// génération abandonnée, ou un bouton pressé après avoir changé de fil, ne
  /// doit jamais réécrire ce qui est ouvert maintenant.
  void _restoreThread(
    List<ChatMessage> previous,
    int generationEpoch,
    int? conversationId,
  ) {
    if (!_isCurrentThread(generationEpoch, conversationId)) {
      return;
    }
    setState(() {
      _messages
        ..clear()
        ..addAll(previous);
      _isGenerating = false;
      // L'enregistrement suit ce qui est affiché : sans cela, le fichier
      // garderait la version tronquée.
      _syncActiveConversation();
    });
  }

  /// Termine proprement un fil quitté pendant sa génération.
  ///
  /// Ne touche qu'à la conversation visée : elle n'est plus forcément à
  /// l'écran, et celle qui l'est n'a rien demandé. Le texte reçu avant
  /// l'abandon y reste, avec ce qui a mis fin à la réponse, et la version
  /// qu'un remplacement venait d'effacer y redevient reprenable.
  void _settleAbandonedThread({
    required int? conversationId,
    required int generationEpoch,
    required String response,
    required List<ChatMessage>? replaced,
    required GenerationOutcome outcome,
  }) {
    if (!mounted || conversationId == null) {
      return;
    }
    // Une génération plus récente a pris ce fil : elle seule décide de son
    // contenu. Sans ce garde, une opération périmée écrasait la nouvelle.
    if (_lastGeneration[conversationId] != generationEpoch) {
      return;
    }
    // Fil supprimé entre-temps : il ne doit surtout pas renaître.
    final conversation = _conversationById(conversationId);
    if (conversation == null) {
      return;
    }
    final messages = conversation.messages;
    if (messages.isEmpty || messages.last.role != ChatRole.assistant) {
      // Le fil ne se termine pas par une réponse en attente : il a été repris
      // ailleurs, et rien ici ne sait mieux que lui ce qu'il doit contenir.
      return;
    }

    final head = messages.take(messages.length - 1);
    final List<ChatMessage> repaired;
    if (response.isNotEmpty) {
      // Le texte reçu avant l'abandon vaut mieux qu'une bulle vide, et il dit
      // ce qu'il est : interrompu, écourté ou en échec.
      repaired = <ChatMessage>[
        ...head,
        ChatMessage(
          role: ChatRole.assistant,
          content: response,
          outcome: outcome,
          outcomeReason: outcome == GenerationOutcome.incomplete
              ? messages.last.outcomeReason
              : null,
        ),
      ];
    } else if (replaced != null) {
      // Un remplacement qui n'a rien donné : la version d'avant revient
      // d'elle-même, il n'y a pas deux versions à conserver.
      repaired = <ChatMessage>[...replaced];
    } else {
      // Un envoi ordinaire : la question reste, sans réponse.
      repaired = <ChatMessage>[...head];
    }

    setState(() {
      conversation.messages = repaired;
      if (response.isNotEmpty && replaced != null) {
        // Les deux versions restent : celle qu'on a reçue et celle qu'elle
        // remplaçait. C'est le retour dans ce fil qui permettra de choisir.
        conversation.previousMessages = List<ChatMessage>.unmodifiable(
          replaced,
        );
      }
      conversation.updatedAt = DateTime.now();
      if (conversationId == _activeConversationId) {
        // Le fil est encore affiché : c'est l'opération qui est périmée, pas
        // la conversation. L'écran doit montrer ce qui sera enregistré.
        _messages
          ..clear()
          ..addAll(repaired);
        _isGenerating = false;
      }
      _persistConversations();
    });
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
                'consulter le web. Configure une API personnelle Anthropic, '
                'Google ou OpenAI.',
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
    if (status == DictationStatus.cancelled) {
      // Le micro a été relâché pendant la préparation : l'utilisateur sait ce
      // qu'il a fait, il n'y a rien à lui annoncer.
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
    // L'arrêt part même si le micro n'est pas encore ouvert : c'est ce qui
    // annule une préparation en cours.
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
            title: _topBarTitle,
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
                      isGenerating: _isGenerating,
                      speakingText: _speakingText,
                      editingIndex: _editingIndex,
                      editController: _editController,
                      actions: _MessageActions(
                        onCopy: _copyMessage,
                        onRate: _rateMessage,
                        onSpeak: (message) => unawaited(_speakMessage(message)),
                        onShare: (message) => unawaited(_shareMessage(message)),
                        onRegenerate: (index) => unawaited(_regenerate(index)),
                        onShowSources: _showSources,
                        onEdit: _startEdit,
                        onCancelEdit: _cancelEdit,
                        onSubmitEdit: () => unawaited(_submitEdit()),
                      ),
                    ),
            ),
          ),
          if (_restoringModel) const _RestoringModelBanner(),
          if (_previousVersion != null)
            _PreviousVersionBanner(
              // Le fil appartient à l'envoi en cours tant qu'il dure.
              enabled: !_operationInFlight,
              onRestore: _swapWithPreviousVersion,
              onForget: _forgetPreviousVersion,
            ),
          if (_queued.isNotEmpty)
            _QueuedStrip(
              queued: List<_Outgoing>.unmodifiable(_queued),
              canRetry: !_isGenerating && !_sending,
              onRetry: () => unawaited(_drainQueue()),
              onResume: _resumeQueued,
              onRemove: _removeQueued,
            ),
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
