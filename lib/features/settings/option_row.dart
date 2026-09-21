// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';

import 'package:foxllm/core/theme/fox_palette.dart';

/// Une rangée à cocher dans un écran de réglages : un libellé, une phrase
/// d'explication, et la pastille qui dit si c'est le choix en place.
///
/// [leading] n'existe que pour les déclinaisons, qui montrent un aperçu. Une
/// langue n'a rien à montrer d'elle-même, et une vignette vide à sa place
/// déséquilibrerait la rangée.
class OptionRow extends StatelessWidget {
  const OptionRow({
    required this.label,
    required this.description,
    required this.isSelected,
    required this.onSelected,
    this.leading,
    super.key,
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
