import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/personal_api_settings_provider.dart';
import '../../core/theme/fox_palette.dart';
import '../../core/theme/theme_provider.dart';
import '../local_models/local_models_screen.dart';
import 'about_screen.dart';
import 'appearance_screen.dart';
import 'personal_api_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fox = context.fox;

    final personalApiState = ref.watch(personalApiSettingsProvider);
    final personalApiSubtitle = personalApiState.when(
      data: (settings) {
        if (!settings.isConfigured) {
          return 'BYOK · non configurée';
        }
        return settings.useInChat
            ? 'Active · ${settings.model}'
            : 'Configurée · ${settings.model}';
      },
      loading: () => 'BYOK · chargement…',
      error: (_, _) => 'BYOK · configuration indisponible',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Paramètres',
          style: TextStyle(color: fox.textPrimary, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
        children: <Widget>[
          const _SettingsSectionTitle('Modèles et fournisseurs'),
          const SizedBox(height: 8),
          _SettingsCard(
            children: <Widget>[
              _SettingsTile(
                icon: Icons.memory_outlined,
                title: 'Modèles locaux',
                subtitle: 'GGUF · llama.cpp',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const LocalModelsScreen(),
                    ),
                  );
                },
              ),
              Divider(height: 1, color: fox.border),
              _SettingsTile(
                icon: Icons.cloud_outlined,
                title: 'API personnelle',
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
          const _SettingsSectionTitle('Application'),
          const SizedBox(height: 8),
          _SettingsCard(
            children: <Widget>[
              _SettingsTile(
                icon: Icons.palette_outlined,
                title: 'Apparence',
                subtitle: ref.watch(foxThemeProvider).label,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const AppearanceScreen(),
                    ),
                  );
                },
              ),
              Divider(height: 1, color: fox.border),
              const _SettingsTile(
                icon: Icons.shield_outlined,
                title: 'Confidentialité',
                subtitle: 'Clés et données conservées sur l’appareil',
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SettingsSectionTitle('FoxGPT'),
          const SizedBox(height: 8),
          _SettingsCard(
            children: <Widget>[
              _SettingsTile(
                icon: Icons.info_outline,
                title: 'À propos',
                subtitle: 'Conditions d’utilisation et confidentialité',
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
