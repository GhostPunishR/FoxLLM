// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

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

  /// Texte en cours de lecture, `null` au repos.
  ///
  /// Sert à savoir quelle réponse afficher comme parlante, et à distinguer
  /// une seconde demande sur le même message, qui arrête, d'une demande sur
  /// un autre, qui bascule.
  String? _speaking;

  String? get speaking => _speaking;

  /// Lit [text], ou s'arrête si c'est déjà lui qui est en cours.
  ///
  /// Rend `true` si la lecture a démarré, `false` si elle s'est arrêtée ou
  /// si l'appareil n'a pas de voix utilisable.
  Future<bool> toggle(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (_speaking != null) {
      final wasSame = _speaking == trimmed;
      await stop();
      if (wasSame) {
        return false;
      }
    }

    try {
      if (!_configured) {
        await _tts.setLanguage('fr-FR');
        // La lecture se termine, ou s'interrompt : dans les deux cas, plus
        // rien ne parle et le bouton doit le montrer.
        _tts.setCompletionHandler(() => _speaking = null);
        _tts.setCancelHandler(() => _speaking = null);
        _tts.setErrorHandler((dynamic _) => _speaking = null);
        _configured = true;
      }
      _speaking = trimmed;
      await _tts.speak(trimmed);
      return true;
    } catch (_) {
      _speaking = null;
      return false;
    }
  }

  Future<void> stop() async {
    _speaking = null;
    try {
      await _tts.stop();
    } catch (_) {
      // Rien à rattraper : l'arrêt d'une voix absente n'a pas d'effet.
    }
  }
}

final speechProvider = Provider<Speech>((ref) {
  final speech = Speech();
  ref.onDispose(speech.stop);
  return speech;
});
