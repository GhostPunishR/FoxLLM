class LocalModelFile {
  const LocalModelFile({
    required this.fileName,
    required this.path,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String fileName;
  final String path;
  final int sizeBytes;
  final DateTime modifiedAt;

  String get displayName => localModelDisplayName(fileName);
}

/// Nom lisible d'un modèle, à partir de son chemin complet ou de son seul nom
/// de fichier : l'extension `.gguf` n'apprend rien à qui lit un sous-titre.
String localModelDisplayName(String pathOrFileName) {
  final separator = pathOrFileName.lastIndexOf('/');
  final fileName = separator == -1
      ? pathOrFileName
      : pathOrFileName.substring(separator + 1);
  return fileName.toLowerCase().endsWith('.gguf')
      ? fileName.substring(0, fileName.length - 5)
      : fileName;
}
