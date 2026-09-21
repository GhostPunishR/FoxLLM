// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:foxllm/core/l10n/fox_language.dart';
import 'package:foxllm/core/l10n/fox_language_labels.dart';
import 'package:foxllm/core/l10n/language_provider.dart';
import 'package:foxllm/core/theme/fox_palette.dart';
import 'package:foxllm/core/theme/fox_theme.dart';
import 'package:foxllm/core/theme/fox_theme_labels.dart';
import 'package:foxllm/core/theme/theme_provider.dart';
import 'package:foxllm/core/ui/fox_mark.dart';
import 'package:foxllm/l10n/app_localizations.dart';

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fox = context.fox;
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(foxThemeProvider);
    final language = ref.watch(foxLanguageProvider);

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
            _Option(
              label: theme.label(l10n),
              description: theme.description(l10n),
              isSelected: theme == selected,
              onSelected: () =>
                  unawaited(ref.read(foxThemeProvider.notifier).select(theme)),
              leading: _ThemePreview(palette: theme.palette),
            ),
            const SizedBox(height: 14),
          ],
          const SizedBox(height: 18),
          Text(
            l10n.appearanceLanguageTitle,
            style: TextStyle(
              color: fox.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.appearanceLanguageIntro,
            style: TextStyle(
              color: fox.textSecondary,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          for (final option in FoxLanguage.values) ...<Widget>[
            _Option(
              label: option.label(l10n),
              description: option.description(l10n),
              isSelected: option == language,
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

/// Une rangée à cocher : déclinaison ou langue, même forme.
///
/// [leading] n'existe que pour les déclinaisons, qui montrent un aperçu. Une
/// langue n'a rien à montrer d'elle-même, et une vignette vide à sa place
/// déséquilibrerait la rangée.
class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.description,
    required this.isSelected,
    required this.onSelected,
    this.leading,
  });

  final String label;
  final String description;
  final bool isSelected;
  final VoidCallback onSelected;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;

    return Semantics(
      selected: isSelected,
      button: true,
      label: label,
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
                if (leading != null) ...<Widget>[
                  leading!,
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        label,
                        style: TextStyle(
                          color: fox.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
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
