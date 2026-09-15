// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

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

  /// Identifie la lecture en cours.
  ///
  /// Préparer la voix demande un aller-retour avec Android. Un arrêt survenu
  /// pendant cette attente ne trouvait rien à arrêter, et la lecture partait
  /// quand même une fois l'attente finie.
  int _epoch = 0;

  /// Sérialise les démarrages.
  ///
  /// Le moteur n'a qu'une voix : deux démarrages qui se chevauchent se
  /// marchent dessus. Un démarrage attend donc que le précédent ait fini de
  /// se mettre en place.
  ///
  /// L'arrêt, lui, ne prend pas ce verrou : il doit agir tout de suite, même
  /// si un démarrage est encore suspendu à une réponse d'Android.
  final SerialLock _engine = SerialLock();

  /// `speak()` ne rend la main qu'à la fin de l'énoncé qu'il a lancé.
  ///
  /// C'est le seul signal du moteur rattaché à une lecture précise, et c'est
  /// donc lui qui éteint l'état. Les rappels, eux, n'emportent aucun
  /// identifiant : `speak.onComplete`, `speak.onCancel` et `speak.onError`
  /// arrivent nus, et le plugin ne garde qu'un jeu de rappels, celui posé en
  /// dernier. Aucun compteur Dart ne peut donc leur attribuer un énoncé, et un
  /// rappel en retard n'est pas distinguable d'un rappel à l'heure.
  ///
  /// Faux tant que le moteur n'a pas accepté ce mode : les rappels reprennent
  /// alors la main, faute de mieux. Voir [_onEngineIdle].
  ///
  /// Lu dans `FlutterTtsPlugin.kt` de `flutter_tts` 4.2.5, la version résolue :
  /// le plugin ne garde la réponse de `speak` que si la file est en
  /// `QUEUE_FLUSH`, ce qui est son réglage par défaut et que FoxLLM ne change
  /// jamais. Il la rend à 1 sur `onDone`, à 0 sur `onError` et à 0 dans le
  /// traitement de `stop`.
  ///
  /// Limite connue, non corrigeable côté Dart : `onStop` ne rend pas cette
  /// réponse. Un énoncé interrompu autrement que par `stop`, par une perte du
  /// focus audio ou un arrêt du service par exemple, laisse donc l'appel en
  /// attente et le bouton allumé. Rien n'est perdu pour autant : le bouton
  /// reste une bascule, et le prochain appui, comme un changement de fil,
  /// remet l'état à zéro.
  bool _awaitsCompletion = false;

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
  /// si l'appareil n'a pas de voix utilisable. La lecture, elle, continue
  /// après ce retour : sa fin passe par [speaking].
  Future<bool> toggle(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _disposed) {
      return Future<bool>.value(false);
    }

    // L'identité est prise avant la moindre attente : un arrêt demandé
    // pendant la préparation doit annuler ce démarrage, pas le suivant.
    final previous = _speaking.value;
    final epoch = ++_epoch;

    if (previous != null) {
      // Le moteur n'a qu'une voix : celle qui parle se tait tout de suite.
      // Sans cela, la lecture suivante attendrait la fin d'un texte qu'on ne
      // veut plus entendre, puisque `speak()` ne revient qu'à ce moment-là.
      _speaking.value = null;
      unawaited(_silence());
      if (previous == trimmed) {
        // Rappuyer sur la réponse en cours l'arrête, sans en relancer une.
        return Future<bool>.value(false);
      }
    }

    return _engine.run(() => _speak(trimmed, epoch));
  }

  Future<bool> _speak(String trimmed, int epoch) async {
    bool stale() => epoch != _epoch || _disposed;
    if (stale()) {
      return false;
    }

    try {
      if (!_configured) {
        await _configure();
        if (stale()) {
          return false;
        }
      }
      _speaking.value = trimmed;
      // La lecture est suivie de côté : `speak()` ne revient qu'à la fin de
      // l'énoncé, et l'appelant, lui, attend seulement que la voix parte.
      unawaited(_follow(_tts.speak(trimmed), epoch));
      return true;
    } catch (_) {
      if (!stale()) {
        _speaking.value = null;
      }
      return false;
    }
  }

  Future<void> _configure() async {
    await _tts.setLanguage('fr-FR');
    try {
      // Demandé avant le premier énoncé : le moteur garde alors la réponse de
      // `speak` jusqu'à la fin de la lecture, arrêt et panne compris. C'est ce
      // qui rattache une fin à l'énoncé qui l'a produite.
      await _tts.awaitSpeakCompletion(true);
      _awaitsCompletion = true;
    } catch (_) {
      // Plateforme qui ne le propose pas : les rappels redeviennent le seul
      // signal disponible, avec leur imprécision.
      _awaitsCompletion = false;
    }
    // La lecture se termine, ou s'interrompt : dans les deux cas, plus rien ne
    // parle et le bouton doit le montrer.
    _tts.setCompletionHandler(_onEngineIdle);
    _tts.setCancelHandler(_onEngineIdle);
    _tts.setErrorHandler((dynamic _) => _onEngineIdle());
    _configured = true;
  }

  /// Suit un énoncé jusqu'à sa fin, quelle qu'en soit la cause.
  ///
  /// [utterance] est la réponse de `speak()` pour cet énoncé précis : elle
  /// revient à la fin naturelle, à l'arrêt ou à l'erreur. L'état ne s'éteint
  /// que si cette lecture est encore celle qu'on attend, ce qui est vérifiable
  /// ici, contrairement aux rappels : l'époque est celle de l'appel dont on
  /// tient la réponse.
  Future<void> _follow(Future<dynamic> utterance, int epoch) async {
    try {
      await utterance;
    } catch (_) {
      // Une panne du moteur met fin à la lecture comme le ferait un arrêt.
    }
    if (!_awaitsCompletion || epoch != _epoch) {
      return;
    }
    _speaking.value = null;
  }

  /// Le moteur annonce qu'il ne parle plus, sans dire de quel énoncé.
  ///
  /// Ignoré quand [_awaitsCompletion] tient : la réponse de `speak()` dit la
  /// même chose et sait de qui elle parle. Agir en plus sur un événement
  /// anonyme ne pourrait qu'éteindre la mauvaise lecture, un rappel de la
  /// précédente pouvant arriver après le départ de la suivante.
  ///
  /// Sans ce mode, il reste le seul signal : on l'applique alors, en sachant
  /// qu'il peut éteindre une lecture qui vient de commencer.
  void _onEngineIdle() {
    if (_awaitsCompletion) {
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
    await _silence();
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
