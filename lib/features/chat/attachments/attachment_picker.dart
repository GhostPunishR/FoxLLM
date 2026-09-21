// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:foxllm/l10n/app_localizations.dart';
import 'package:foxllm/llm/model/chat_attachment.dart';

/// Fichier choisi, avant d'être rangé dans l'espace privé.
class PickedAttachment {
  const PickedAttachment({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;
}

/// Refus explicite et lisible : le fichier choisi ne peut pas être joint.
class AttachmentException implements Exception {
  const AttachmentException(this.message, {this.sizeLimitMegabytes});

  /// Le message en français, gardé pour la trace et comme dernier recours.
  final String message;

  /// Plafond dépassé, quand c'en est la cause.
  final String? sizeLimitMegabytes;

  String describe(AppLocalizations l10n) {
    final limit = sizeLimitMegabytes;
    return limit == null ? message : l10n.attachmentTooLarge(limit);
  }

  @override
  String toString() => message;
}

/// Taille maximale d'une pièce jointe.
///
/// Une image part encodée en base64 dans la requête, ce qui l'alourdit d'un
/// tiers ; au-delà, l'envoi échouerait après une longue attente.
const int maxAttachmentBytes = 8 * 1024 * 1024;

/// Origine d'une pièce jointe, telle que proposée dans le menu « + ».
enum AttachmentSource { file, gallery, camera }

/// Ouvre le sélecteur du système correspondant à la source demandée.
///
/// Isolé derrière un provider pour que l'écran de chat reste testable sans
/// les sélecteurs natifs.
class AttachmentPicker {
  AttachmentPicker({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  /// Renvoie `null` si l'utilisateur annule.
  Future<PickedAttachment?> pick(
    AttachmentSource source, {
    required String dialogTitle,
  }) async {
    return switch (source) {
      AttachmentSource.file => _pickFile(dialogTitle),
      AttachmentSource.gallery => _pickImage(ImageSource.gallery),
      AttachmentSource.camera => _pickImage(ImageSource.camera),
    };
  }

  /// [dialogTitle] vient de l'écran : le sélecteur est celui du système, et
  /// son titre doit suivre la langue de l'interface comme le reste.
  Future<PickedAttachment?> _pickFile(String dialogTitle) async {
    final picked = await FilePicker.pickFile(dialogTitle: dialogTitle);
    if (picked == null) {
      return null;
    }
    _checkSize(await picked.length());
    return PickedAttachment(
      name: picked.name,
      mimeType: mimeTypeForFileName(picked.name),
      bytes: await picked.readAsBytes(),
    );
  }

  Future<PickedAttachment?> _pickImage(ImageSource source) async {
    final picked = await _imagePicker.pickImage(
      source: source,
      // Les modèles multimodaux ramènent de toute façon l'image à quelques
      // centaines de pixels : envoyer 12 Mpx ne ferait qu'allonger la requête.
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 88,
    );
    if (picked == null) {
      return null;
    }
    final bytes = await picked.readAsBytes();
    _checkSize(bytes.length);
    final name = picked.name.isEmpty ? 'photo.jpg' : picked.name;
    return PickedAttachment(
      name: name,
      mimeType: picked.mimeType ?? mimeTypeForFileName(name),
      bytes: bytes,
    );
  }

  void _checkSize(int bytes) {
    if (bytes > maxAttachmentBytes) {
      throw AttachmentException(
        'Pièce jointe trop volumineuse '
        '(${maxAttachmentBytes ~/ (1024 * 1024)} Mo maximum).',
        sizeLimitMegabytes: '${maxAttachmentBytes ~/ (1024 * 1024)}',
      );
    }
  }
}

final attachmentPickerProvider = Provider<AttachmentPicker>(
  (ref) => AttachmentPicker(),
);
