// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Contenu texte d'un fichier joint au message en cours de rédaction.
class TextAttachment {
  const TextAttachment({required this.name, required this.text});

  final String name;
  final String text;
}

/// Refus explicite et lisible : le fichier choisi ne peut pas être joint.
class AttachmentException implements Exception {
  const AttachmentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Taille maximale d'une pièce jointe.
///
/// Au-delà, le fichier dépasserait de toute façon la fenêtre de contexte du
/// modèle et ferait échouer la génération après une longue attente.
const int maxAttachmentBytes = 128 * 1024;

/// Langage Markdown déduit de l'extension, pour la coloration du bloc.
const Map<String, String> _languageByExtension = <String, String>{
  'c': 'c',
  'cpp': 'cpp',
  'cc': 'cpp',
  'cs': 'csharp',
  'css': 'css',
  'dart': 'dart',
  'go': 'go',
  'h': 'c',
  'hpp': 'cpp',
  'html': 'html',
  'ini': 'ini',
  'java': 'java',
  'js': 'javascript',
  'json': 'json',
  'kt': 'kotlin',
  'md': 'markdown',
  'php': 'php',
  'py': 'python',
  'rb': 'ruby',
  'rs': 'rust',
  'sh': 'bash',
  'sql': 'sql',
  'swift': 'swift',
  'toml': 'toml',
  'ts': 'typescript',
  'tsx': 'tsx',
  'xml': 'xml',
  'yaml': 'yaml',
  'yml': 'yaml',
};

/// Décode un fichier choisi en texte exploitable par le modèle.
///
/// Lève une [AttachmentException] plutôt que de renvoyer des caractères de
/// remplacement : mieux vaut refuser un binaire que d'envoyer du bruit au
/// modèle et gaspiller la fenêtre de contexte.
TextAttachment decodeTextAttachment(String name, Uint8List bytes) {
  if (bytes.length > maxAttachmentBytes) {
    throw AttachmentException(
      'Fichier trop volumineux (${maxAttachmentBytes ~/ 1024} Ko maximum).',
    );
  }
  if (bytes.contains(0)) {
    throw const AttachmentException(
      'Seuls les fichiers texte peuvent être joints pour l’instant.',
    );
  }

  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    throw const AttachmentException(
      'Seuls les fichiers texte peuvent être joints pour l’instant.',
    );
  }

  if (text.trim().isEmpty) {
    throw const AttachmentException('Ce fichier est vide.');
  }
  return TextAttachment(name: name, text: text);
}

/// Met la pièce jointe en forme pour le composer : un bloc de code annoté.
String formatAttachment(TextAttachment attachment) {
  final dot = attachment.name.lastIndexOf('.');
  final extension = dot > 0
      ? attachment.name.substring(dot + 1).toLowerCase()
      : '';
  final language = _languageByExtension[extension] ?? '';
  // La clôture fermante retire le retour à la ligne final du fichier pour ne
  // pas laisser de ligne vide dans le bloc.
  final body = attachment.text.trimRight();
  return 'Fichier joint : ${attachment.name}\n```$language\n$body\n```\n';
}

/// Ouvre le sélecteur de fichiers du système et décode le fichier choisi.
///
/// Isolé derrière un provider pour que l'écran de chat reste testable sans
/// dépendre du sélecteur natif.
class AttachmentPicker {
  const AttachmentPicker();

  /// Renvoie `null` si l'utilisateur annule.
  Future<TextAttachment?> pickTextFile() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Choisir un fichier texte',
    );
    if (picked == null) {
      return null;
    }
    if (await picked.length() > maxAttachmentBytes) {
      throw AttachmentException(
        'Fichier trop volumineux (${maxAttachmentBytes ~/ 1024} Ko maximum).',
      );
    }
    return decodeTextAttachment(picked.name, await picked.readAsBytes());
  }
}

final attachmentPickerProvider = Provider<AttachmentPicker>(
  (ref) => const AttachmentPicker(),
);
