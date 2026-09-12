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

  String get displayName => fileName.toLowerCase().endsWith('.gguf')
      ? fileName.substring(0, fileName.length - 5)
      : fileName;
}
