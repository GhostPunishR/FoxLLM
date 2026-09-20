// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

/// Affiche la **première** erreur rencontrée, et non la dernière.
///
/// Quand une construction échoue, Flutter remplace le sous-arbre abîmé par un
/// écran d'erreur, puis démonte ce qui l'entourait. Ce démontage échoue à son
/// tour, et c'est cette seconde erreur, sans rapport avec la cause, qui reste
/// à l'écran. L'utilisateur lit une conséquence ; la cause a défilé dans un
/// journal qu'il n'a pas.
///
/// Ce relevé garde la première et l'affiche à la place des suivantes, avec le
/// début de sa pile d'appels : de quoi nommer le fichier et la ligne depuis un
/// téléphone, sans câble ni outil.
///
/// Réservé aux versions de débogage. En distribution, Flutter garde son écran
/// discret, et une pile d'appels n'aiderait personne.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Première erreur reçue depuis le lancement, gardée telle quelle.
@visibleForTesting
FlutterErrorDetails? firstError;

/// Remet le relevé à zéro. Utile entre deux tests.
@visibleForTesting
void forgetFirstError() => firstError = null;

/// Branche le relevé et l'écran qui le montre.
void installFirstErrorScreen() {
  if (!kDebugMode) {
    return;
  }

  final previousHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    firstError ??= details;
    previousHandler?.call(details);
  };

  ErrorWidget.builder = (details) {
    // `details` décrit l'erreur du moment, qui n'est pas forcément la
    // première : c'est tout l'objet de ce relevé.
    final shown = firstError ?? details;
    return FirstErrorScreen(details: shown);
  };
}

/// Écran rouge qui donne l'erreur d'origine et sa provenance.
///
/// Volontairement sans thème, sans police choisie et sans image : il doit
/// s'afficher quand tout le reste a échoué, y compris la palette.
class FirstErrorScreen extends StatelessWidget {
  const FirstErrorScreen({super.key, required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    final stack = details.stack
        ?.toString()
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        // Les premières lignes suffisent à nommer le coupable, et tiennent
        // sur un écran de téléphone.
        .take(12)
        .join('\n');

    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF8B1010),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Première erreur',
                    style: TextStyle(
                      color: Color(0xFFFFE08A),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    details.exceptionAsString(),
                    style: const TextStyle(
                      color: Color(0xFFFFF3CC),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  if (details.library != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      'pendant : ${details.library}',
                      style: const TextStyle(
                        color: Color(0xFFFFE08A),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (stack != null && stack.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 16),
                    const Text(
                      'Pile d’appels',
                      style: TextStyle(
                        color: Color(0xFFFFE08A),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      stack,
                      style: const TextStyle(
                        color: Color(0xFFFFF3CC),
                        fontSize: 11,
                        height: 1.35,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
