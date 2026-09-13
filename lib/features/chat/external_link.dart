// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:url_launcher/url_launcher.dart';

/// Ouvre un lien d'une réponse dans le navigateur du système.
///
/// Seuls `http` et `https` sont acceptés : une réponse de modèle est du texte
/// non vérifié, et laisser passer n'importe quel schéma reviendrait à lui
/// confier le déclenchement d'intentions arbitraires sur l'appareil.
///
/// Rend `false` si le lien est refusé ou si rien ne sait l'ouvrir.
Future<bool> openExternalLink(Uri url) async {
  if (url.scheme != 'http' && url.scheme != 'https') {
    return false;
  }
  try {
    return await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
