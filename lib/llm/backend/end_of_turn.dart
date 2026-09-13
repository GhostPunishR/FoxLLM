// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

/// Coupe une réponse locale au premier marqueur de fin de tour.
///
/// Le gabarit du modèle suffit normalement : le modèle termine sur son jeton
/// de fin, et `llama.cpp` arrête la boucle. Mais un GGUF peut porter un
/// gabarit inexact, ou écrire ses balises en texte ordinaire plutôt qu'en
/// jetons spéciaux. Le moteur ne voit alors rien à arrêter, et le modèle
/// continue en jouant les deux rôles du dialogue.
///
/// Ce filtre rattrape ce cas côté Dart : dès qu'un marqueur apparaît, le texte
/// s'arrête là et la génération est abandonnée.
class EndOfTurnFilter {
  /// Marqueurs des familles de gabarits répandues : ChatML, Llama 3, Phi,
  /// Mistral, et les formats en `<|rôle|>`.
  static const markers = <String>[
    '<|im_end|>',
    '<|im_start|>',
    '<|eot_id|>',
    '<|start_header_id|>',
    '<|end_of_text|>',
    '<|endoftext|>',
    '<|end|>',
    '<|system|>',
    '<|user|>',
    '<|assistant|>',
    '</s>',
    '[INST]',
  ];

  static final int _longestMarker = markers
      .map((marker) => marker.length)
      .reduce((a, b) => a > b ? a : b);

  String _pending = '';
  bool _finished = false;

  /// Vrai dès qu'un marqueur a été rencontré : plus rien ne doit être affiché.
  bool get isFinished => _finished;

  /// Le texte affichable apporté par [chunk], éventuellement vide.
  String add(String chunk) {
    if (_finished || chunk.isEmpty) {
      return '';
    }

    _pending += chunk;

    final marker = _firstMarker(_pending);
    if (marker >= 0) {
      _finished = true;
      final text = _pending.substring(0, marker);
      _pending = '';
      return text;
    }

    // Un marqueur peut arriver à cheval sur deux morceaux : la fin qui
    // ressemble à un début de marqueur attend le morceau suivant.
    final hold = _holdBackFrom(_pending);
    final text = _pending.substring(0, hold);
    _pending = _pending.substring(hold);
    return text;
  }

  /// Ce qui restait en attente quand le flux se termine sans marqueur.
  String flush() {
    if (_finished) {
      return '';
    }
    final rest = _pending;
    _pending = '';
    return rest;
  }

  static int _firstMarker(String text) {
    var first = -1;
    for (final marker in markers) {
      final index = text.indexOf(marker);
      if (index >= 0 && (first < 0 || index < first)) {
        first = index;
      }
    }
    return first;
  }

  /// Position à partir de laquelle le texte pourrait amorcer un marqueur.
  ///
  /// Rend la longueur du texte quand rien ne l'amorce : la réponse courante
  /// s'affiche alors sans retard, mot après mot.
  static int _holdBackFrom(String text) {
    final earliest = text.length - _longestMarker + 1;
    for (
      var index = text.length - 1;
      index >= 0 && index >= earliest;
      index--
    ) {
      final tail = text.substring(index);
      for (final marker in markers) {
        if (marker.startsWith(tail)) {
          return index;
        }
      }
    }
    return text.length;
  }
}
