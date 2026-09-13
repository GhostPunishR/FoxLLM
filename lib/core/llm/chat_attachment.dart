// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

/// Pièce jointe d'un message, conservée à côté de la conversation.
///
/// Le fichier lui-même vit dans l'espace privé de l'application ; le message
/// ne garde que de quoi le retrouver et l'afficher. Recopier son contenu dans
/// l'historique ferait grossir le fichier de conversations à chaque image.
class ChatAttachment {
  const ChatAttachment({
    required this.name,
    required this.path,
    required this.mimeType,
    required this.sizeBytes,
  });

  /// Nom d'origine, affiché dans le fil.
  final String name;

  /// Chemin dans l'espace privé de l'application.
  final String path;

  final String mimeType;
  final int sizeBytes;

  /// Une image, que seul un modèle multimodal peut lire.
  bool get isImage => mimeType.startsWith('image/');

  /// Un fichier texte, dont le contenu accompagne la requête.
  bool get isText => mimeType.startsWith('text/');

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'path': path,
    'mimeType': mimeType,
    'sizeBytes': sizeBytes,
  };

  /// Rend `null` si l'entrée est inexploitable, pour qu'une pièce jointe
  /// abîmée n'emporte pas la conversation qui la porte.
  static ChatAttachment? fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      return null;
    }
    final name = value['name'];
    final path = value['path'];
    final mimeType = value['mimeType'];
    final sizeBytes = value['sizeBytes'];
    if (name is! String || path is! String || mimeType is! String) {
      return null;
    }
    return ChatAttachment(
      name: name,
      path: path,
      mimeType: mimeType,
      sizeBytes: sizeBytes is int ? sizeBytes : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChatAttachment &&
      other.name == name &&
      other.path == path &&
      other.mimeType == mimeType &&
      other.sizeBytes == sizeBytes;

  @override
  int get hashCode => Object.hash(name, path, mimeType, sizeBytes);

  @override
  String toString() => 'ChatAttachment($name, $mimeType, $sizeBytes o)';
}

/// Taille lisible, pour l'étiquette d'une pièce jointe.
String formatAttachmentSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).round()} Ko';
  }
  return '$bytes o';
}

/// Type MIME déduit de l'extension, quand le sélecteur n'en donne pas.
String mimeTypeForFileName(String name) {
  final dot = name.lastIndexOf('.');
  final extension = dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
  return switch (extension) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'bmp' => 'image/bmp',
    'txt' || 'log' || 'csv' => 'text/plain',
    'md' => 'text/markdown',
    'json' => 'text/json',
    'yaml' || 'yml' => 'text/yaml',
    'xml' => 'text/xml',
    'html' || 'htm' => 'text/html',
    'css' => 'text/css',
    'dart' ||
    'py' ||
    'js' ||
    'ts' ||
    'tsx' ||
    'jsx' ||
    'java' ||
    'kt' ||
    'c' ||
    'cc' ||
    'cpp' ||
    'h' ||
    'hpp' ||
    'cs' ||
    'go' ||
    'rs' ||
    'rb' ||
    'php' ||
    'swift' ||
    'sh' ||
    'sql' ||
    'toml' ||
    'ini' => 'text/plain',
    _ => 'application/octet-stream',
  };
}
