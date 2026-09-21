// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:foxllm/core/theme/fox_palette.dart';
import 'package:foxllm/core/theme/fox_theme.dart';
import 'package:foxllm/core/theme/fox_theme_labels.dart';
import 'package:foxllm/core/theme/theme_provider.dart';
import 'package:foxllm/core/ui/fox_mark.dart';
import 'package:foxllm/features/settings/option_row.dart';
import 'package:foxllm/l10n/app_localizations.dart';

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fox = context.fox;
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(foxThemeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.appearanceTitle,
          style: TextStyle(color: fox.textPrimary, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
        children: <Widget>[
          Text(
            l10n.appearanceThemeIntro,
            style: TextStyle(
              color: fox.textSecondary,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          for (final theme in FoxTheme.values) ...<Widget>[
            OptionRow(
              label: theme.label(l10n),
              description: theme.description(l10n),
              isSelected: theme == selected,
              onSelected: () =>
                  unawaited(ref.read(foxThemeProvider.notifier).select(theme)),
              leading: _ThemePreview(palette: theme.palette),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

/// Aperçu miniature : fond, bulle de message et logo de la déclinaison.
class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.palette});

  final FoxPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.borderStrong),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const FoxMark(size: 26),
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 8,
            decoration: BoxDecoration(
              color: palette.userBubble,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 26,
            height: 8,
            decoration: BoxDecoration(
              color: palette.accent,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ],
      ),
    );
  }
}
