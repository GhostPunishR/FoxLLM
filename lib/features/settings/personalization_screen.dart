// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:foxllm/llm/model/personalization.dart';
import 'package:foxllm/core/theme/fox_palette.dart';

/// Écran où l'utilisateur décrit comment son IA doit répondre.
///
/// Le texte saisi est envoyé en message système à chaque requête, avant
/// l'historique : il s'applique donc aussi bien au moteur local qu'à une API
/// personnelle, et aux conversations déjà ouvertes.
class PersonalizationScreen extends ConsumerStatefulWidget {
  const PersonalizationScreen({super.key});

  @override
  ConsumerState<PersonalizationScreen> createState() =>
      _PersonalizationScreenState();
}

class _PersonalizationScreenState extends ConsumerState<PersonalizationScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(personalizationProvider),
    );
    unawaited(_syncWithStoredValue());
  }

  /// Les instructions sont relues du stockage de façon asynchrone : si elles
  /// arrivent après l'ouverture de l'écran, le champ doit les refléter plutôt
  /// que de rester vide et de les écraser à l'enregistrement.
  Future<void> _syncWithStoredValue() async {
    final stored = await ref.read(personalizationProvider.notifier).resolved();
    if (mounted && _controller.text.isEmpty && stored.isNotEmpty) {
      _controller.text = stored;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(personalizationProvider.notifier).save(_controller.text);
    if (!mounted) {
      return;
    }
    final saved = ref.read(personalizationProvider);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            saved.isEmpty
                ? 'Instructions effacées.'
                : 'Instructions enregistrées.',
          ),
        ),
      );
  }

  void _applyPreset(PersonalizationPreset preset) {
    final current = _controller.text.trim();
    setState(() {
      _controller.text = current.isEmpty
          ? preset.instructions
          : '$current\n${preset.instructions}';
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final fox = context.fox;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Personnalisation',
          style: TextStyle(color: fox.textPrimary, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
        children: <Widget>[
          Text(
            'Décris comment FoxLLM doit te répondre : ton, longueur, langue, '
            'rôle à tenir. Ces consignes accompagnent chaque message, dans '
            'toutes les conversations.',
            style: TextStyle(
              color: fox.textSecondary,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: fox.surfaceInput,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: fox.border),
            ),
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, child) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    TextField(
                      controller: _controller,
                      minLines: 6,
                      maxLines: 12,
                      maxLength: maxInstructionsLength,
                      // Le compteur intégré doublonnerait avec celui d'en bas.
                      buildCounter:
                          (
                            context, {
                            required currentLength,
                            required isFocused,
                            required maxLength,
                          }) => null,
                      inputFormatters: <TextInputFormatter>[
                        LengthLimitingTextInputFormatter(maxInstructionsLength),
                      ],
                      keyboardAppearance: Theme.of(context).brightness,
                      style: TextStyle(color: fox.textPrimary, fontSize: 16),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText:
                            'Exemple : réponds en français, de façon concise, '
                            'et donne toujours un exemple de code commenté.',
                        hintStyle: TextStyle(
                          color: fox.textTertiary,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                    ),
                    Text(
                      '${value.text.characters.length} / '
                      '$maxInstructionsLength',
                      style: TextStyle(color: fox.textTertiary, fontSize: 12),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Pour démarrer',
            style: TextStyle(
              color: fox.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final preset in personalizationPresets)
                ActionChip(
                  label: Text(preset.label),
                  onPressed: () => _applyPreset(preset),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  onPressed: () => unawaited(_save()),
                  child: const Text('Enregistrer'),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () {
                  _controller.clear();
                  unawaited(_save());
                },
                child: Text(
                  'Effacer',
                  style: TextStyle(color: fox.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.lightbulb_outline, size: 18, color: fox.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sur un modèle local, des consignes très longues réduisent '
                  'la place disponible pour la conversation : quelques phrases '
                  'précises valent mieux qu’un texte détaillé.',
                  style: TextStyle(
                    color: fox.textTertiary,
                    fontSize: 13,
                    height: 1.45,
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
