// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:foxllm/core/app_info.dart';
import 'package:foxllm/core/theme/fox_palette.dart';
import 'package:foxllm/core/ui/external_link.dart';
import 'package:foxllm/core/ui/fox_mark.dart';
import 'package:foxllm/features/settings/about/legal_documents.dart';
import 'package:foxllm/features/settings/about/license_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'À propos',
          style: TextStyle(color: fox.textPrimary, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
        children: <Widget>[
          const SizedBox(height: 12),
          const Center(child: FoxMark(size: 84)),
          const SizedBox(height: 18),
          Center(
            child: Text(
              'FoxLLM',
              style: TextStyle(
                color: fox.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Version $foxLlmVersion',
              style: TextStyle(color: fox.textSecondary, fontSize: 14),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              foxLlmCopyright,
              style: TextStyle(color: fox.textTertiary, fontSize: 13),
            ),
          ),
          const SizedBox(height: 28),
          _AboutCard(
            children: <Widget>[
              _AboutTile(
                icon: Icons.description_outlined,
                title: termsOfUseDocument.title,
                subtitle: 'Ce que tu acceptes en utilisant FoxLLM',
                document: termsOfUseDocument,
              ),
              Divider(height: 1, color: fox.border),
              _AboutTile(
                icon: Icons.privacy_tip_outlined,
                title: privacyPolicyDocument.title,
                subtitle: 'Ce que deviennent tes données',
                document: privacyPolicyDocument,
              ),
              Divider(height: 1, color: fox.border),
              _AboutTile(
                icon: Icons.code,
                title: 'Code source',
                subtitle: foxLlmSourceUrl.replaceFirst('https://', ''),
                // L'AGPL demande que le code reste accessible à qui reçoit le
                // programme : l'adresse est donnée ici, pas seulement dans le
                // dépôt.
                onTap: () =>
                    unawaited(openExternalLink(Uri.parse(foxLlmSourceUrl))),
              ),
              Divider(height: 1, color: fox.border),
              _AboutTile(
                icon: Icons.balance_outlined,
                title: 'Licence',
                subtitle: 'GNU Affero General Public License v3',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const LicenseScreen(),
                  ),
                ),
              ),
              Divider(height: 1, color: fox.border),
              _AboutTile(
                icon: Icons.inventory_2_outlined,
                title: 'Licences tierces',
                subtitle: 'Bibliothèques utilisées par FoxLLM',
                // Page fournie par Flutter : elle rassemble les licences que
                // les dépendances imposent de faire figurer dans l'application.
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'FoxLLM',
                  applicationVersion: 'Version $foxLlmVersion',
                  applicationIcon: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: FoxMark(size: 52),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;
    return Material(
      color: fox.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: fox.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _AboutTile extends StatelessWidget {
  const _AboutTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.document,
    this.onTap,
  }) : assert(
         document != null || onTap != null,
         'une entrée doit mener quelque part',
       );

  final IconData icon;
  final String title;
  final String subtitle;

  /// Document légal à ouvrir, quand l'entrée en présente un.
  final LegalDocument? document;

  /// Destination libre, pour les entrées qui n'ouvrent pas un document.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;
    return ListTile(
      minLeadingWidth: 28,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      leading: Icon(icon, color: fox.textPrimary),
      title: Text(
        title,
        style: TextStyle(
          color: fox.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: fox.textSecondary, fontSize: 13),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: fox.textTertiary),
      onTap: () {
        final legalDocument = document;
        if (legalDocument == null) {
          onTap!();
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => LegalDocumentScreen(document: legalDocument),
          ),
        );
      },
    );
  }
}
