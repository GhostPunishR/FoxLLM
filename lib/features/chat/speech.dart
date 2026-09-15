// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:foxllm/core/async/serial_lock.dart';

/// Lecture à voix haute d'une réponse.
///
/// La synthèse est celle d'Android, comme la dictée l'est pour la
/// reconnaissance : FoxLLM ne transporte aucun son et n'en conserve aucun.
/// Selon l'appareil et les voix installées, le service du système peut
/// travailler sur place ou passer par ses propres serveurs.
///
/// Isolée derrière un provider pour que l'écran de chat reste testable sans
/// moteur vocal.
class Speech {
  Speech({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _configured = false;

  /// Identifie l'opération en cours.
  ///
  /// Préparer la voix demande un aller-retour avec Android. Un arrêt survenu
  /// pendant cette attente ne trouvait rien à arrêter, et la lecture partait
  /// quand même une fois l'attente finie.
  int _epoch = 0;

  /// Sérialise les démarrages.
  ///
  /// Le moteur n'a qu'une voix : deux démarrages qui se chevauchent se
  /// marchent dessus. Un démarrage attend donc la fin du précédent, ce qui
  /// garantit qu'une lecture périmée a fini de se retirer avant que la
  /// suivante commence.
  ///
  /// L'arrêt, lui, ne prend pas ce verrou : il doit agir tout de suite, même
  /// si un démarrage est encore suspendu à une réponse d'Android.
  final SerialLock _engine = SerialLock();

  /// Époque du démarrage à qui appartient le moteur.
  ///
  /// Posée au moment de confier la phrase à la voix. Un démarrage qui se
  /// découvre périmé ne referme le moteur que s'il lui appartient encore :
  /// sinon il coupait la lecture qu'un autre venait de lancer.
  int _owner = 0;

  /// Vrai le temps d'une bascule d'une lecture à l'autre.
  ///
  /// Les rappels de `flutter_tts` ne disent pas de quelle phrase ils parlent :
  /// `setCompletionHandler` et `setCancelHandler` ne reçoivent aucun
  /// identifiant, et le plugin ne garde que le dernier jeu de rappels posé.
  /// Aucun compteur Dart ne peut donc leur attribuer un événement natif. Ils
  /// sont neutralisés le temps de la bascule, qui est justement le moment où
  /// l'arrêt de la phrase précédente en provoque un qui ne concerne plus
  /// personne.
  bool _switching = false;

  /// Le service est détruit : plus aucune lecture ne doit démarrer.
  bool _disposed = false;

  final ValueNotifier<String?> _speaking = ValueNotifier<String?>(null);

  /// Texte en cours de lecture, `null` au repos.
  ///
  /// Sert à savoir quelle réponse afficher comme parlante, et à distinguer
  /// une seconde demande sur le même message, qui arrête, d'une demande sur
  /// un autre, qui bascule.
  ///
  /// Observable, et non simplement lisible : la lecture s'achève d'elle-même
  /// à la fin du texte, sans que personne n'appelle `stop()`. Un état recopié
  /// ailleurs resterait allumé après la dernière syllabe, faute d'être averti.
  ValueListenable<String?> get speaking => _speaking;

  /// Lit [text], ou s'arrête si c'est déjà lui qui est en cours.
  ///
  /// Rend `true` si la lecture a démarré, `false` si elle s'est arrêtée ou
  /// si l'appareil n'a pas de voix utilisable.
  Future<bool> toggle(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _disposed) {
      return Future<bool>.value(false);
    }
    // L'identité est prise avant l'attente du verrou : un arrêt demandé
    // pendant cette attente doit annuler ce démarrage, pas le suivant.
    final epoch = ++_epoch;
    return _engine.run(() => _speak(trimmed, epoch));
  }

  Future<bool> _speak(String trimmed, int epoch) async {
    bool stale() => epoch != _epoch || _disposed;
    if (stale()) {
      return false;
    }

    final previous = _speaking.value;
    if (previous != null) {
      // Bascule : la phrase en cours s'arrête, et le rappel provoqué par cet
      // arrêt ne doit pas éteindre celle qui part juste après.
      _switching = true;
      _speaking.value = null;
      await _silence();
      if (previous == trimmed) {
        _switching = false;
        return false;
      }
    }

    try {
      if (stale()) {
        return false;
      }
      if (!_configured) {
        await _tts.setLanguage('fr-FR');
        if (stale()) {
          return false;
        }
        // La lecture se termine, ou s'interrompt : dans les deux cas, plus
        // rien ne parle et le bouton doit le montrer.
        _tts.setCompletionHandler(_onEngineIdle);
        _tts.setCancelHandler(_onEngineIdle);
        _tts.setErrorHandler((dynamic _) => _onEngineIdle());
        _configured = true;
      }
      if (stale()) {
        return false;
      }
      _speaking.value = trimmed;
      _owner = epoch;
      await _tts.speak(trimmed);
      if (stale()) {
        // L'arrêt est arrivé pendant le démarrage : la voix a beau être
        // partie, elle se tait tout de suite. Sauf si une autre lecture a
        // pris le moteur entre-temps : la couper serait arrêter la mauvaise.
        if (_owner == epoch) {
          _speaking.value = null;
          await _silence();
        }
        return false;
      }
      return true;
    } catch (_) {
      if (!stale()) {
        _speaking.value = null;
      }
      return false;
    } finally {
      _switching = false;
    }
  }

  /// Le moteur ne parle plus. Ignoré pendant une bascule : le rappel vient
  /// alors de la phrase qu'on vient d'arrêter, pas de celle qui démarre.
  void _onEngineIdle() {
    if (_switching) {
      return;
    }
    _speaking.value = null;
  }

  Future<void> _silence() async {
    try {
      await _tts.stop();
    } catch (_) {
      // Rien à rattraper : l'arrêt d'une voix absente n'a pas d'effet.
    }
  }

  /// Arrête la lecture, et annule un démarrage encore en attente.
  Future<void> stop() async {
    // L'annulation est immédiate, et sans passer par le verrou : un arrêt ne
    // doit pas attendre la fin d'un démarrage qu'Android fait patienter.
    _epoch += 1;
    _speaking.value = null;
    _switching = true;
    try {
      await _silence();
    } finally {
      _switching = false;
    }
  }

  /// Arrête tout et n'accepte plus aucun démarrage.
  ///
  /// L'observable, lui, survit : des écrans s'en détachent encore après la
  /// destruction du service, et retirer un écouteur d'un objet libéré lèverait
  /// une exception.
  Future<void> dispose() async {
    _disposed = true;
    await stop();
  }
}

final speechProvider = Provider<Speech>((ref) {
  final speech = Speech();
  // Seule la lecture est arrêtée, pas l'observable : il vit aussi longtemps
  // que la portée, et le libérer pendant qu'un écran s'en détache encore
  // ferait échouer le retrait de son écouteur.
  ref.onDispose(speech.dispose);
  return speech;
});
