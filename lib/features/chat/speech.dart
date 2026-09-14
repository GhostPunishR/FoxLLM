// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

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

  /// Identifie le démarrage en cours.
  ///
  /// Préparer la voix demande un aller-retour avec Android. Un arrêt survenu
  /// pendant cette attente ne trouvait rien à arrêter, et la lecture partait
  /// quand même une fois l'attente finie.
  int _epoch = 0;

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
  Future<bool> toggle(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (_speaking.value != null) {
      final wasSame = _speaking.value == trimmed;
      await stop();
      if (wasSame) {
        return false;
      }
    }

    // Ce démarrage précis. Tout ce qui survient après une attente n'est
    // appliqué que s'il est encore d'actualité.
    final epoch = ++_epoch;
    bool stale() => epoch != _epoch;

    try {
      if (!_configured) {
        await _tts.setLanguage('fr-FR');
        if (stale()) {
          return false;
        }
        // La lecture se termine, ou s'interrompt : dans les deux cas, plus
        // rien ne parle et le bouton doit le montrer.
        _tts.setCompletionHandler(() => _speaking.value = null);
        _tts.setCancelHandler(() => _speaking.value = null);
        _tts.setErrorHandler((dynamic _) => _speaking.value = null);
        _configured = true;
      }
      if (stale()) {
        return false;
      }
      _speaking.value = trimmed;
      await _tts.speak(trimmed);
      if (stale()) {
        // L'arrêt est arrivé pendant le démarrage : la voix a beau être
        // partie, elle se tait tout de suite.
        _speaking.value = null;
        await _tts.stop();
        return false;
      }
      return true;
    } catch (_) {
      if (!stale()) {
        _speaking.value = null;
      }
      return false;
    }
  }

  /// Arrête la lecture, et annule un démarrage encore en attente.
  Future<void> stop() async {
    _epoch += 1;
    _speaking.value = null;
    try {
      await _tts.stop();
    } catch (_) {
      // Rien à rattraper : l'arrêt d'une voix absente n'a pas d'effet.
    }
  }
}

final speechProvider = Provider<Speech>((ref) {
  final speech = Speech();
  // Seule la lecture est arrêtée, pas l'observable : il vit aussi longtemps
  // que la portée, et le libérer pendant qu'un écran s'en détache encore
  // ferait échouer le retrait de son écouteur.
  ref.onDispose(speech.stop);
  return speech;
});
