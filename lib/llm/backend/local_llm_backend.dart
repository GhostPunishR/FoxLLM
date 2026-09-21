// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:foxllm_native/foxllm_native.dart';

import 'package:foxllm/llm/backend/end_of_turn.dart';
import 'package:foxllm/llm/backend/llm_backend.dart';
import 'package:foxllm/llm/model/chat_message.dart';
import 'package:foxllm/llm/model/generation_settings.dart';

/// Moteur capable de dire qu'une réponse s'est arrêtée avant la fin.
///
/// Un flux accepté puis écourté n'est ni une réussite ni une erreur : le chat
/// a besoin de le savoir pour ne pas présenter un texte partiel comme une
/// réponse entière. Un contrat séparé plutôt qu'une méthode de plus pour tout
/// le monde : un moteur qui ne sait pas distinguer les deux ne doit pas avoir
/// à prétendre le contraire.
abstract interface class IncompleteAwareBackend {
  /// Motif pour lequel la dernière réponse a été écourtée, ou `null`.
  ///
  /// Remis à zéro au début de chaque génération : ce qui est lu appartient
  /// toujours à la dernière, jamais à la précédente.
  String? get incompleteReason;
}

class LocalLlmBackend implements LlmBackend, IncompleteAwareBackend {
  LocalLlmBackend({Future<FoxLlmNativeWorker>? worker})
    : _worker = worker ?? FoxLlmNativeWorker.start();

  final Future<FoxLlmNativeWorker> _worker;
  String? _loadedModelPath;
  String? _incompleteReason;

  /// Clés d'arrêt, choisies pour celles que le chat sait déjà expliquer.
  ///
  /// `length` est la clé que les API distantes emploient pour un plafond de
  /// jetons : le moteur local s'arrête pour la même raison, et il n'y a
  /// aucune raison que l'explication affichée diffère.
  static const _tokenLimitReason = 'length';

  /// La fenêtre du modèle, elle, appelle un autre remède : relever le plafond
  /// n'y changerait rien, il faut alléger la conversation.
  static const _contextLimitReason = 'context_length';

  @override
  String? get incompleteReason => _incompleteReason;

  /// Traduit le motif rendu par le moteur en clé d'affichage.
  ///
  /// Un arrêt demandé n'est pas une réponse écourtée : le chat le tient déjà
  /// pour ce qu'il est, et le redire ici le ferait passer pour une limite
  /// atteinte.
  static String? _reasonFrom(FoxLlmGenerationStats? stats) =>
      switch (stats?.stopReason) {
        FoxLlmStopReason.tokenLimit => _tokenLimitReason,
        FoxLlmStopReason.contextLimit => _contextLimitReason,
        FoxLlmStopReason.endOfText ||
        FoxLlmStopReason.cancelled ||
        null => null,
      };

  @override
  String get id => 'local';

  @override
  String get displayName => 'Modèle local';

  String? get loadedModelPath => _loadedModelPath;

  Future<String> get nativeVersion async => (await _worker).version;

  Future<bool> get isModelLoaded async => (await _worker).isModelLoaded;

  Future<FoxLlmModelInfo?> get modelInfo async => (await _worker).modelInfo;

  Future<FoxLlmGenerationStats?> get lastGenerationStats async =>
      (await _worker).lastGenerationStats;

  Future<void> loadModel(String path) async {
    try {
      await (await _worker).loadModel(path);
      _loadedModelPath = path;
    } catch (_) {
      _loadedModelPath = null;
      rethrow;
    }
  }

  Future<void> unloadModel() async {
    await (await _worker).unloadModel();
    _loadedModelPath = null;
  }

  @override
  Stream<String> generate({
    required List<ChatMessage> messages,
    GenerationSettings settings = const GenerationSettings(),
  }) async* {
    final worker = await _worker;
    final prompt = await _buildPrompt(worker, messages);
    final endOfTurn = EndOfTurnFilter();

    // Ce qui suit appartient à cette génération : le motif de la précédente
    // ne doit pas pouvoir être lu pour celle-ci.
    _incompleteReason = null;

    final stream = worker.generate(
      prompt: prompt,
      temperature: settings.temperature,
      topP: settings.topP,
      maxTokens: settings.maxTokens,
    );

    await for (final chunk in stream) {
      final text = endOfTurn.add(chunk);
      if (text.isNotEmpty) {
        yield text;
      }
      if (endOfTurn.isFinished) {
        // Quitter la boucle annule l'abonnement, ce qui arrête le moteur :
        // inutile de continuer à produire un dialogue que personne ne verra.
        //
        // Le modèle a posé sa marque de fin : la réponse est entière, et le
        // motif reste nul quoi qu'ait relevé le moteur ensuite.
        return;
      }
    }

    final rest = endOfTurn.flush();
    if (rest.isNotEmpty) {
      yield rest;
    }

    // Le relevé est posé avant que le flux se ferme : il porte donc bien sur
    // la génération qui vient de finir. Une génération tombée en erreur n'en
    // produit pas, et n'arrive pas jusqu'ici.
    _incompleteReason = _reasonFrom(worker.lastGenerationStats);
  }

  @override
  Future<void> stop() async {
    (await _worker).stop();
  }

  @override
  Future<void> dispose() async {
    final FoxLlmNativeWorker worker;
    try {
      worker = await _worker;
    } catch (_) {
      // Startup errors are surfaced by the operation that awaited the worker.
      // Cleanup must remain safe when the app is already being disposed.
      return;
    }

    _loadedModelPath = null;
    await worker.dispose();
  }

  /// Met la conversation au format que le modèle chargé attend.
  ///
  /// Le gabarit vient du GGUF lui-même. Inventer un format, comme le faisait
  /// la version précédente, produisait un modèle qui ne reconnaissait pas la
  /// fin de son tour : au lieu de s'arrêter sur son jeton de fin, il
  /// continuait en écrivant les répliques de l'utilisateur et les balises du
  /// format qu'il croyait reconnaître.
  Future<String> _buildPrompt(
    FoxLlmNativeWorker worker,
    List<ChatMessage> messages,
  ) async {
    final turns = <FoxLlmChatMessage>[
      for (final message in messages)
        FoxLlmChatMessage(role: message.role.name, content: message.content),
    ];

    try {
      return await worker.applyChatTemplate(turns);
    } catch (_) {
      // Modèle absent ou gabarit illisible : ChatML reste le format le plus
      // largement reconnu, et vaut mieux qu'un envoi sans aucune structure.
      return _chatMlPrompt(messages);
    }
  }

  static String _chatMlPrompt(List<ChatMessage> messages) {
    final buffer = StringBuffer();
    for (final message in messages) {
      buffer
        ..write('<|im_start|>')
        ..write(message.role.name)
        ..write('\n')
        ..write(message.content)
        ..write('<|im_end|>\n');
    }
    buffer.write('<|im_start|>assistant\n');
    return buffer.toString();
  }
}
