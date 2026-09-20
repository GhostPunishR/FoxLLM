// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:foxllm/features/local_models/gguf_inspection.dart';
import 'package:foxllm/l10n/app_localizations.dart';

/// Met des mots sur un refus d'import.
///
/// Séparé de l'examen lui-même : celui-ci lit des octets et ne connaît aucune
/// langue, tandis que la phrase montrée dépend de l'interface.
String describeGgufRejection(
  GgufRejectedException rejection,
  AppLocalizations l10n,
) => switch (rejection.defect) {
  GgufDefect.notGguf => l10n.ggufNotGguf,
  GgufDefect.unsupportedVersion => l10n.ggufUnsupportedVersion(
    rejection.detail ?? '?',
  ),
  GgufDefect.truncated => l10n.ggufTruncated,
  GgufDefect.noTensors => l10n.ggufNoTensors,
  GgufDefect.noArchitecture => l10n.ggufNoArchitecture,
  GgufDefect.narrowTensorNotFloat32 => l10n.ggufNarrowTensor(
    rejection.detail ?? '?',
  ),
};
