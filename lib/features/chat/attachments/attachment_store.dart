// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:foxllm/llm/model/chat_attachment.dart';

/// Range les pièces jointes dans l'espace privé de l'application.
///
/// Le fichier choisi vit ailleurs (cache du sélecteur, galerie, dossier
/// partagé) et peut disparaître d'un instant à l'autre. En garder
/// une copie est ce qui permet de rouvrir une conversation des semaines plus
/// tard et d'y retrouver ses pièces jointes.
class AttachmentStore {
  AttachmentStore({Directory? root}) : _root = root;

  final Directory? _root;
  Directory? _resolved;

  Future<Directory> _directory() async {
    final cached = _resolved;
    if (cached != null) {
      return cached;
    }
    final base = _root ?? await getApplicationSupportDirectory();
    final directory = Directory('${base.path}/attachments');
    await directory.create(recursive: true);
    _resolved = directory;
    return directory;
  }

  /// Copie les octets et rend la pièce jointe à conserver.
  Future<ChatAttachment> save({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final directory = await _directory();
    final file = File('${directory.path}/${_uniqueName(name)}');
    await file.writeAsBytes(bytes, flush: true);
    return ChatAttachment(
      name: name,
      path: file.path,
      mimeType: mimeType,
      sizeBytes: bytes.length,
    );
  }

  Future<Uint8List?> read(ChatAttachment attachment) async {
    final file = File(attachment.path);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  /// Efface les copies d'une conversation supprimée.
  Future<void> delete(Iterable<ChatAttachment> attachments) async {
    for (final attachment in attachments) {
      try {
        final file = File(attachment.path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Une copie impossible à effacer ne doit pas interrompre la
        // suppression des suivantes.
      }
    }
  }

  /// Préfixe horodaté : deux fichiers du même nom ne s'écrasent pas.
  String _uniqueName(String name) {
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final salt = math.Random().nextInt(1 << 16);
    return '${stamp}_${salt}_$safe';
  }
}

final attachmentStoreProvider = Provider<AttachmentStore>(
  (ref) => AttachmentStore(),
);
