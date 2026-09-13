// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Issue d'une demande de dictée.
enum DictationStatus {
  /// La reconnaissance écoute.
  listening,

  /// L'utilisateur a refusé l'accès au micro.
  denied,

  /// L'appareil n'a pas de service de reconnaissance vocale utilisable.
  unavailable,
}

/// Dictée vocale du composer.
///
/// La reconnaissance est celle d'Android : FoxGPT ne transporte aucun son
/// lui-même, mais le service du système peut envoyer l'audio à ses propres
/// serveurs selon l'appareil et les paquets de langue installés. La politique
/// de confidentialité le dit, faute de pouvoir le garantir.
///
/// Isolée derrière un provider pour que l'écran de chat reste testable sans
/// micro.
class Dictation {
  Dictation({SpeechToText? speech}) : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  bool _initialized = false;

  bool get isListening => _speech.isListening;

  /// Démarre l'écoute et rend le texte reconnu au fil de la parole.
  ///
  /// Les résultats partiels sont transmis aussi : voir ses mots s'écrire est
  /// ce qui permet de corriger sa phrase sans attendre la fin.
  Future<DictationStatus> start({
    required void Function(String text) onText,
    String localeId = 'fr_FR',
  }) async {
    if (!_initialized) {
      try {
        _initialized = await _speech.initialize(
          onError: (_) {},
          onStatus: (_) {},
        );
      } catch (_) {
        _initialized = false;
      }
      if (!_initialized) {
        // `initialize` rend faux aussi bien pour un refus de permission que
        // pour un appareil sans service : sans distinction possible, le
        // message d'aide couvre les deux.
        return DictationStatus.unavailable;
      }
    }
    if (!await _speech.hasPermission) {
      return DictationStatus.denied;
    }

    await _speech.listen(
      onResult: (result) => onText(result.recognizedWords),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
        localeId: localeId,
      ),
    );
    return DictationStatus.listening;
  }

  Future<void> stop() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
  }
}

final dictationProvider = Provider<Dictation>((ref) {
  final dictation = Dictation();
  ref.onDispose(() => dictation.stop());
  return dictation;
});
