// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/fox_palette.dart';
import '../../core/theme/fox_theme.dart';
import '../../core/theme/theme_provider.dart';
import '../chat/fox_mark.dart';

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fox = context.fox;
    final selected = ref.watch(foxThemeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Apparence',
          style: TextStyle(color: fox.textPrimary, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
        children: <Widget>[
          Text(
            'Deux déclinaisons aux couleurs du renard. Le choix est conservé '
            'entre deux lancements.',
            style: TextStyle(
              color: fox.textSecondary,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          for (final theme in FoxTheme.values) ...<Widget>[
            _ThemeOption(
              theme: theme,
              isSelected: theme == selected,
              onSelected: () =>
                  unawaited(ref.read(foxThemeProvider.notifier).select(theme)),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.theme,
    required this.isSelected,
    required this.onSelected,
  });

  final FoxTheme theme;
  final bool isSelected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;

    return Semantics(
      selected: isSelected,
      button: true,
      label: theme.label,
      child: Material(
        color: fox.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: isSelected ? fox.accent : fox.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onSelected,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                _ThemePreview(palette: theme.palette),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        theme.label,
                        style: TextStyle(
                          color: fox.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        theme.description,
                        style: TextStyle(
                          color: fox.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isSelected ? fox.accent : fox.textTertiary,
                ),
              ],
            ),
          ),
        ),
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
