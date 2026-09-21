// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:foxllm/core/l10n/fox_language.dart';
import 'package:foxllm/core/l10n/fox_language_labels.dart';
import 'package:foxllm/core/l10n/language_provider.dart';
import 'package:foxllm/core/theme/fox_palette.dart';
import 'package:foxllm/features/settings/option_row.dart';
import 'package:foxllm/l10n/app_localizations.dart';

/// Le choix de langue de toute l'interface.
///
/// Il a son propre écran, et non une section au bas de l'Apparence : la langue
/// ne se cherche pas sous les couleurs.
class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fox = context.fox;
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(foxLanguageProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.languageTitle,
          style: TextStyle(color: fox.textPrimary, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
        children: <Widget>[
          Text(
            l10n.languageIntro,
            style: TextStyle(
              color: fox.textSecondary,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          for (final option in FoxLanguage.values) ...<Widget>[
            OptionRow(
              label: option.label(l10n),
              description: option.description(l10n),
              isSelected: option == selected,
              onSelected: () => unawaited(
                ref.read(foxLanguageProvider.notifier).select(option),
              ),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}
