// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:foxllm/core/async/serial_lock.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Issue d'une demande de dictée.
enum DictationStatus {
  /// La reconnaissance écoute.
  listening,

  /// L'utilisateur a refusé l'accès au micro.
  denied,

  /// L'appareil n'a pas de service de reconnaissance vocale utilisable.
  unavailable,

  /// Le micro a été relâché pendant la préparation.
  ///
  /// Ni un refus ni une panne : il n'y a rien à signaler à l'utilisateur, qui
  /// vient lui-même d'annuler.
  cancelled,
}

/// Dictée vocale du composer.
///
/// La reconnaissance est celle d'Android : FoxLLM ne transporte aucun son
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

  /// Identifie le démarrage en cours.
  ///
  /// L'initialisation et la vérification de permission demandent chacune un
  /// aller-retour avec Android. Relâcher le micro pendant ces attentes ne
  /// trouvait rien à arrêter, et l'écoute s'ouvrait ensuite toute seule.
  int _epoch = 0;

  /// Sérialise les démarrages.
  ///
  /// Il n'y a qu'un micro : deux ouvertures qui se chevauchent se marchent
  /// dessus. Un démarrage attend donc la fin du précédent, ce qui garantit
  /// qu'une écoute périmée a fini de se refermer avant que la suivante
  /// commence.
  ///
  /// L'arrêt, lui, ne prend pas ce verrou : relâcher le micro doit agir tout
  /// de suite, même si une ouverture attend encore une réponse d'Android.
  final SerialLock _engine = SerialLock();

  /// Époque du démarrage à qui appartient le micro.
  ///
  /// Posée au moment de l'ouvrir. Un démarrage qui se découvre périmé ne le
  /// referme que s'il lui appartient encore : sinon il coupait l'écoute qu'un
  /// autre venait d'ouvrir.
  int _owner = 0;

  /// Le service est détruit : plus aucune écoute ne doit démarrer.
  bool _disposed = false;

  bool get isListening => _speech.isListening;

  /// Démarre l'écoute et rend le texte reconnu au fil de la parole.
  ///
  /// Les résultats partiels sont transmis aussi : voir ses mots s'écrire est
  /// ce qui permet de corriger sa phrase sans attendre la fin.
  Future<DictationStatus> start({
    required void Function(String text) onText,
    String localeId = 'fr_FR',
  }) {
    if (_disposed) {
      return Future<DictationStatus>.value(DictationStatus.cancelled);
    }
    // Ce démarrage précis, identifié avant l'attente du verrou : un
    // relâchement pendant cette attente doit l'annuler, pas annuler le
    // suivant.
    final epoch = ++_epoch;
    return _engine.run(
      () => _listen(epoch: epoch, onText: onText, localeId: localeId),
    );
  }

  Future<DictationStatus> _listen({
    required int epoch,
    required void Function(String text) onText,
    required String localeId,
  }) async {
    bool stale() => epoch != _epoch || _disposed;
    if (stale()) {
      return DictationStatus.cancelled;
    }

    if (!_initialized) {
      try {
        _initialized = await _speech.initialize(
          onError: (_) {},
          onStatus: (_) {},
        );
      } catch (_) {
        _initialized = false;
      }
      if (stale()) {
        return DictationStatus.cancelled;
      }
      if (!_initialized) {
        // `initialize` rend faux aussi bien pour un refus de permission que
        // pour un appareil sans service : sans distinction possible, le
        // message d'aide couvre les deux.
        return DictationStatus.unavailable;
      }
    }
    final permitted = await _speech.hasPermission;
    if (stale()) {
      return DictationStatus.cancelled;
    }
    if (!permitted) {
      return DictationStatus.denied;
    }

    _owner = epoch;
    await _speech.listen(
      // Un résultat d'une écoute abandonnée n'a plus rien à remplir.
      onResult: (result) {
        if (!stale()) {
          onText(result.recognizedWords);
        }
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
        localeId: localeId,
      ),
    );
    if (stale()) {
      // Le micro s'est ouvert après le relâchement : on le referme aussitôt.
      // Sauf si une autre écoute l'a pris entre-temps : la refermer serait
      // couper la mauvaise.
      if (_owner == epoch) {
        await _speech.stop();
      }
      return DictationStatus.cancelled;
    }
    return DictationStatus.listening;
  }

  /// Arrête l'écoute, et annule un démarrage encore en attente.
  ///
  /// L'ancien garde sur `isListening` ne voyait rien à arrêter tant que le
  /// micro n'était pas ouvert, ce qui laissait passer exactement le cas
  /// gênant : le relâchement pendant la préparation.
  Future<void> stop() async {
    // L'annulation est immédiate, et sans passer par le verrou : relâcher le
    // micro ne doit pas attendre la fin d'une ouverture qu'Android fait
    // patienter.
    _epoch += 1;
    if (_speech.isListening) {
      await _speech.stop();
    }
  }

  /// Arrête l'écoute et n'accepte plus aucun démarrage.
  Future<void> dispose() async {
    _disposed = true;
    await stop();
  }
}

final dictationProvider = Provider<Dictation>((ref) {
  final dictation = Dictation();
  ref.onDispose(dictation.dispose);
  return dictation;
});
