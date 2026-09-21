// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:foxllm/core/l10n/fox_language_labels.dart';
import 'package:foxllm/core/l10n/language_provider.dart';
import 'package:foxllm/core/theme/fox_palette.dart';
import 'package:foxllm/core/theme/fox_theme_labels.dart';
import 'package:foxllm/core/theme/theme_provider.dart';
import 'package:foxllm/features/local_models/current_local_model.dart';
import 'package:foxllm/features/local_models/local_models_screen.dart';
import 'package:foxllm/features/settings/about/about_screen.dart';
import 'package:foxllm/features/settings/appearance_screen.dart';
import 'package:foxllm/features/settings/history_screen.dart';
import 'package:foxllm/features/settings/language_screen.dart';
import 'package:foxllm/features/settings/personal_api_screen.dart';
import 'package:foxllm/features/settings/personalization_screen.dart';
import 'package:foxllm/l10n/app_localizations.dart';
import 'package:foxllm/llm/model/personalization.dart';
import 'package:foxllm/llm/personal_api/personal_api_settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fox = context.fox;
    final l10n = AppLocalizations.of(context);

    final instructions = ref.watch(personalizationProvider);
    // Le sous-titre nomme le modèle en place : « llama.cpp » désignait le
    // moteur, une information que l'écran des modèles donne déjà.
    final localModelSubtitle = ref
        .watch(currentLocalModelProvider)
        .when(
          data: (name) =>
              name == null ? l10n.localModelNone : l10n.localModelNamed(name),
          loading: () => l10n.localModelLoading,
          error: (_, _) => l10n.localModelUnavailable,
        );
    final personalApiState = ref.watch(personalApiSettingsProvider);
    final personalApiSubtitle = personalApiState.when(
      data: (settings) {
        if (!settings.isConfigured) {
          return l10n.personalApiNotConfigured;
        }
        return settings.useInChat
            ? l10n.personalApiActive(settings.model)
            : l10n.personalApiConfigured(settings.model);
      },
      loading: () => l10n.personalApiLoading,
      error: (_, _) => l10n.personalApiUnavailable,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.settingsTitle,
          style: TextStyle(color: fox.textPrimary, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
        children: <Widget>[
          _SettingsSectionTitle(l10n.settingsProvidersSection),
          const SizedBox(height: 8),
          _SettingsCard(
            children: <Widget>[
              _SettingsTile(
                icon: Icons.memory_outlined,
                title: l10n.settingsLocalModels,
                subtitle: localModelSubtitle,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const LocalModelsScreen(),
                    ),
                  );
                  // Un modèle a pu être chargé ou déchargé entre-temps.
                  ref.invalidate(currentLocalModelProvider);
                },
              ),
              Divider(height: 1, color: fox.border),
              _SettingsTile(
                icon: Icons.cloud_outlined,
                title: l10n.settingsPersonalApi,
                subtitle: personalApiSubtitle,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const PersonalApiScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SettingsSectionTitle(l10n.settingsAppSection),
          const SizedBox(height: 8),
          _SettingsCard(
            children: <Widget>[
              _SettingsTile(
                icon: Icons.palette_outlined,
                title: l10n.appearanceTitle,
                subtitle: ref.watch(foxThemeProvider).label(l10n),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const AppearanceScreen(),
                    ),
                  );
                },
              ),
              Divider(height: 1, color: fox.border),
              _SettingsTile(
                icon: Icons.translate_rounded,
                title: l10n.languageTitle,
                subtitle: ref.watch(foxLanguageProvider).label(l10n),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const LanguageScreen(),
                    ),
                  );
                },
              ),
              Divider(height: 1, color: fox.border),
              _SettingsTile(
                icon: Icons.history_rounded,
                title: l10n.historyTitle,
                subtitle: l10n.historySubtitle,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const HistoryScreen(),
                    ),
                  );
                },
              ),
              Divider(height: 1, color: fox.border),
              _SettingsTile(
                icon: Icons.tune_rounded,
                title: l10n.settingsPersonalization,
                subtitle: instructions.isEmpty
                    ? l10n.settingsPersonalizationHint
                    : l10n.settingsPersonalizationActive,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const PersonalizationScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SettingsSectionTitle('FoxLLM'),
          const SizedBox(height: 8),
          _SettingsCard(
            children: <Widget>[
              _SettingsTile(
                icon: Icons.info_outline,
                title: l10n.settingsAbout,
                subtitle: l10n.settingsAboutHint,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const AboutScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: context.fox.textSecondary,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

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

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;
    final enabled = onTap != null;

    return ListTile(
      onTap: onTap,
      minLeadingWidth: 28,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      leading: Icon(icon, color: enabled ? fox.textPrimary : fox.textTertiary),
      title: Text(
        title,
        style: TextStyle(
          color: enabled ? fox.textPrimary : fox.textSecondary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: fox.textSecondary, fontSize: 13),
      ),
      trailing: enabled
          ? Icon(Icons.chevron_right_rounded, color: fox.textTertiary)
          : null,
    );
  }
}
