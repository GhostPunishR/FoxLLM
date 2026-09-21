// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:foxllm/core/app_info.dart';
import 'package:foxllm/core/theme/fox_palette.dart';
import 'package:foxllm/l10n/app_localizations.dart';

/// Texte intégral de la licence, lu depuis le fichier `LICENSE` du dépôt.
///
/// Le fichier de la racine est embarqué comme ressource plutôt que recopié
/// dans le code : deux exemplaires d'une licence finissent toujours par
/// diverger, et c'est celui du dépôt qui fait foi.
Future<String> loadLicenseText() => rootBundle.loadString('LICENSE');

class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key, this.loader = loadLicenseText});

  /// Lecture du texte, remplaçable pour vérifier l'affichage sans dépendre du
  /// disque.
  final Future<String> Function() loader;

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  /// Lecture lancée une fois : la relancer à chaque `build` relirait la
  /// ressource à chaque frame de défilement.
  late final Future<String> _license = widget.loader();

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Licence',
          style: TextStyle(color: fox.textPrimary, fontWeight: FontWeight.w700),
        ),
      ),
      body: FutureBuilder<String>(
        future: _license,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Message(
              text: AppLocalizations.of(context).licenseUnreadable,
            );
          }
          final license = snapshot.data;
          if (license == null) {
            // La lecture prend quelques millisecondes : un indicateur de
            // chargement ne ferait que clignoter.
            return const SizedBox.shrink();
          }
          // Le texte fait une trentaine de milliers de caractères : découpé en
          // paragraphes, il n'est construit qu'au fil du défilement.
          final paragraphs = license
              .split(RegExp(r'\n\s*\n'))
              .map((paragraph) => paragraph.trimRight())
              .where((paragraph) => paragraph.trim().isNotEmpty)
              .toList(growable: false);

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
            itemCount: paragraphs.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        foxLlmCopyright,
                        style: TextStyle(
                          color: fox.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context).licenseNotice,
                        style: TextStyle(
                          color: fox.textSecondary,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: SelectableText(
                  paragraphs[index - 1],
                  style: TextStyle(
                    color: fox.textPrimary.withValues(alpha: 0.86),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        style: TextStyle(
          color: context.fox.textSecondary,
          fontSize: 15,
          height: 1.5,
        ),
      ),
    );
  }
}
