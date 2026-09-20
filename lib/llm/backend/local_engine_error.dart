// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:foxllm/l10n/app_localizations.dart';

/// Ce que le moteur local peut refuser, et pourquoi.
///
/// Le pont natif ne rend qu'une chaîne, écrite en anglais dans le C++, qui
/// remontait telle quelle jusqu'au bandeau du chat : « Prompt exceeds the
/// model context window. » au milieu d'une application française, et c'est
/// pourtant le refus qu'un utilisateur de modèle local rencontre le plus
/// souvent.
///
/// La correspondance se fait sur le texte d'origine faute de code d'erreur
/// dans l'interface native. C'est fragile par nature, d'où le contrôle de
/// dépôt qui relit le C++ et refuse qu'un message y apparaisse sans figurer
/// ici : la seule façon d'en ajouter un sans le traduire est de faire tomber
/// l'intégration continue.
enum LocalEngineFailure {
  contextFull('Prompt exceeds the model context window.'),
  contextExhausted('llama.cpp ran out of context while reading the prompt.'),
  modelUnreadable('llama.cpp could not load the GGUF model.'),
  outOfMemory('llama.cpp could not create an inference context.'),
  decodeFailed('llama.cpp failed while decoding.'),
  encodeFailed('llama.cpp failed to encode the prompt.'),
  samplerFailed('llama.cpp could not create a sampler.'),
  tokenizeFailed('Unable to tokenize the prompt.'),
  noModelLoaded('No GGUF model is loaded.'),
  noModel('No model is loaded.'),
  modelPathEmpty('Model path is empty.'),
  unsupportedPlatform(
    'llama.cpp local inference is currently available only on Android arm64.',
  ),
  emptyPrompt('Prompt is empty.'),
  nothingToFormat('No message to format.'),
  missingCallback('Token callback is null.'),
  badTemperature('Temperature must be greater than or equal to zero.'),
  badTopP('Top-p must be in the interval (0, 1].'),
  badMaxTokens('Max tokens must be greater than zero.');

  const LocalEngineFailure(this.nativeMessage);

  /// Le message exact que le C++ écrit dans `last_error`.
  final String nativeMessage;

  /// Reconnaît un message du moteur local, ou `null` si ce n'en est pas un.
  static LocalEngineFailure? match(String message) {
    final trimmed = message.trim();
    for (final failure in LocalEngineFailure.values) {
      if (failure.nativeMessage == trimmed) {
        return failure;
      }
    }
    return null;
  }

  String describe(AppLocalizations l10n) => switch (this) {
    LocalEngineFailure.contextFull => l10n.localEngineContextFull,
    LocalEngineFailure.contextExhausted => l10n.localEngineContextExhausted,
    LocalEngineFailure.modelUnreadable => l10n.localEngineModelUnreadable,
    LocalEngineFailure.outOfMemory => l10n.localEngineOutOfMemory,
    LocalEngineFailure.decodeFailed => l10n.localEngineDecodeFailed,
    LocalEngineFailure.encodeFailed => l10n.localEngineEncodeFailed,
    LocalEngineFailure.samplerFailed => l10n.localEngineSamplerFailed,
    LocalEngineFailure.tokenizeFailed => l10n.localEngineTokenizeFailed,
    LocalEngineFailure.noModelLoaded => l10n.localEngineNoModelLoaded,
    LocalEngineFailure.noModel => l10n.localEngineNoModel,
    LocalEngineFailure.modelPathEmpty => l10n.localEngineModelPathEmpty,
    LocalEngineFailure.unsupportedPlatform =>
      l10n.localEngineUnsupportedPlatform,
    LocalEngineFailure.emptyPrompt => l10n.localEngineEmptyPrompt,
    LocalEngineFailure.nothingToFormat => l10n.localEngineNothingToFormat,
    LocalEngineFailure.missingCallback => l10n.localEngineMissingCallback,
    LocalEngineFailure.badTemperature => l10n.localEngineBadTemperature,
    LocalEngineFailure.badTopP => l10n.localEngineBadTopP,
    LocalEngineFailure.badMaxTokens => l10n.localEngineBadMaxTokens,
  };
}
