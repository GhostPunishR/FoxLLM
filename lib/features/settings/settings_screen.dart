import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/personal_api_settings_provider.dart';
import '../local_models/local_models_screen.dart';
import 'personal_api_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const background = Color(0xFF0B0B0B);
    const muted = Color(0xFF969696);
    const orange = Color(0xFFFC6117);

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
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Paramètres',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
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
              const Divider(height: 1, color: Color(0xFF292929)),
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
          const _SettingsCard(
            children: <Widget>[
              _SettingsTile(
                icon: Icons.dark_mode_outlined,
                title: 'Apparence',
                subtitle: 'Sombre',
              ),
              Divider(height: 1, color: Color(0xFF292929)),
              _SettingsTile(
                icon: Icons.shield_outlined,
                title: 'Confidentialité',
                subtitle: 'Clés et données conservées sur l’appareil',
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SettingsSectionTitle('FoxGPT'),
          const SizedBox(height: 8),
          const _SettingsCard(
            children: <Widget>[
              _SettingsTile(
                icon: Icons.info_outline,
                title: 'À propos',
                subtitle: 'FoxGPT · local + BYOK',
              ),
            ],
          ),
          const SizedBox(height: 26),
          const Center(
            child: Text(
              'FoxGPT',
              style: TextStyle(color: muted, fontSize: 13, letterSpacing: 0.2),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 28,
              height: 3,
              decoration: BoxDecoration(
                color: orange,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
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
      style: const TextStyle(
        color: Color(0xFF989898),
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
    return Material(
      color: const Color(0xFF181818),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF242424)),
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
    final enabled = onTap != null;

    return ListTile(
      onTap: onTap,
      minLeadingWidth: 28,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      leading: Icon(
        icon,
        color: enabled ? Colors.white : const Color(0xFFB0B0B0),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: enabled ? Colors.white : const Color(0xFFE0E0E0),
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Color(0xFF909090), fontSize: 13),
      ),
      trailing: enabled
          ? const Icon(Icons.chevron_right_rounded, color: Color(0xFF8D8D8D))
          : null,
    );
  }
}
