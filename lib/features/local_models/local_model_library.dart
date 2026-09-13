// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'local_model_file.dart';

typedef LocalModelDirectoryProvider = Future<Directory> Function();
typedef LocalModelImportProgress =
    void Function(int copiedBytes, int? totalBytes);

class LocalModelLibrary {
  LocalModelLibrary({LocalModelDirectoryProvider? applicationSupportDirectory})
    : _applicationSupportDirectory =
          applicationSupportDirectory ?? getApplicationSupportDirectory;

  final LocalModelDirectoryProvider _applicationSupportDirectory;
  final Set<String> _activePartialPaths = <String>{};
  final Set<String> _reservedDestinations = <String>{};

  Future<List<LocalModelFile>> listModels() async {
    final directory = await _modelsDirectory();
    final models = <LocalModelFile>[];

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }

      if (_isPartialImport(entity.path)) {
        final partialPath = entity.absolute.path;
        if (!_activePartialPaths.contains(partialPath)) {
          await entity.delete();
        }
        continue;
      }

      if (!_isGguf(entity.path)) {
        continue;
      }

      final stat = await entity.stat();
      if (stat.type != FileSystemEntityType.file) {
        continue;
      }

      models.add(
        LocalModelFile(
          fileName: _fileName(entity.path),
          path: entity.absolute.path,
          sizeBytes: stat.size,
          modifiedAt: stat.modified,
        ),
      );
    }

    models.sort(
      (left, right) =>
          left.fileName.toLowerCase().compareTo(right.fileName.toLowerCase()),
    );
    return models;
  }

  Future<LocalModelFile> importModel({
    required String fileName,
    required Stream<List<int>> bytes,
    int? expectedSizeBytes,
    LocalModelImportProgress? onProgress,
  }) async {
    final sanitizedName = _sanitizeFileName(fileName);
    if (!_isGguf(sanitizedName)) {
      throw FormatException(
        'Le fichier sélectionné doit être un modèle .gguf.',
      );
    }

    final directory = await _modelsDirectory();
    final reservations = <String>{};
    final File destination;
    try {
      destination = await _reserveDestination(
        directory,
        sanitizedName,
        reservations,
      );
    } catch (_) {
      _reservedDestinations.removeAll(reservations);
      rethrow;
    }

    final partial = File(
      '${destination.path}.part-${DateTime.now().microsecondsSinceEpoch}',
    );
    final partialPath = partial.absolute.path;
    RandomAccessFile? output;
    var copiedBytes = 0;

    _activePartialPaths.add(partialPath);
    try {
      output = await partial.open(mode: FileMode.write);
      await for (final chunk in bytes) {
        if (chunk.isEmpty) {
          continue;
        }
        await output.writeFrom(chunk);
        copiedBytes += chunk.length;
        onProgress?.call(copiedBytes, expectedSizeBytes);
      }

      await output.flush();
      await output.close();
      output = null;

      if (copiedBytes == 0) {
        throw const FormatException('Le modèle GGUF sélectionné est vide.');
      }
      if (expectedSizeBytes != null &&
          expectedSizeBytes > 0 &&
          copiedBytes != expectedSizeBytes) {
        throw StateError(
          'Import GGUF incomplet : $copiedBytes octets copiés sur '
          '$expectedSizeBytes attendus.',
        );
      }

      final imported = await partial.rename(destination.path);
      return await _describe(imported);
    } catch (_) {
      if (output != null) {
        await output.close();
      }
      if (await partial.exists()) {
        await partial.delete();
      }
      rethrow;
    } finally {
      _activePartialPaths.remove(partialPath);
      _reservedDestinations.removeAll(reservations);
    }
  }

  Future<void> deleteModel(LocalModelFile model) async {
    final directory = await _modelsDirectory();
    final candidate = File(model.path).absolute;

    if (candidate.parent.path != directory.absolute.path ||
        candidate.path !=
            File(
              '${directory.path}${Platform.pathSeparator}${model.fileName}',
            ).absolute.path ||
        !_isGguf(candidate.path)) {
      throw StateError(
        'Refus de supprimer un fichier hors de la bibliothèque FoxGPT.',
      );
    }

    if (await candidate.exists()) {
      await candidate.delete();
    }
  }

  Future<Directory> _modelsDirectory() async {
    final support = await _applicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}models',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// Réserve un nom de destination libre et le marque occupé jusqu'à la fin de
  /// l'import.
  ///
  /// La réservation passe par `Set.add`, qui est synchrone : deux imports du
  /// même nom lancés en parallèle ne peuvent pas obtenir la même destination,
  /// alors qu'un simple `exists()` les laissait s'entrelacer et le second
  /// `rename()` écrasait silencieusement le modèle du premier.
  Future<File> _reserveDestination(
    Directory directory,
    String fileName,
    Set<String> reservations,
  ) async {
    final extensionIndex = fileName.toLowerCase().lastIndexOf('.gguf');
    final baseName = fileName.substring(0, extensionIndex);
    var suffix = 1;

    while (true) {
      final candidate = File(
        suffix == 1
            ? '${directory.path}${Platform.pathSeparator}$fileName'
            : '${directory.path}${Platform.pathSeparator}$baseName ($suffix).gguf',
      );
      final reservedPath = candidate.absolute.path;

      if (_reservedDestinations.add(reservedPath)) {
        reservations.add(reservedPath);
        if (!await candidate.exists()) {
          return candidate;
        }
      }
      suffix += 1;
    }
  }

  Future<LocalModelFile> _describe(File file) async {
    final stat = await file.stat();
    return LocalModelFile(
      fileName: _fileName(file.path),
      path: file.absolute.path,
      sizeBytes: stat.size,
      modifiedAt: stat.modified,
    );
  }

  String _sanitizeFileName(String value) {
    final leaf = value.split(RegExp(r'[/\\]')).last.trim();
    final sanitized = leaf.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') {
      throw const FormatException('Nom de fichier GGUF invalide.');
    }
    return sanitized;
  }

  bool _isGguf(String value) => value.toLowerCase().endsWith('.gguf');

  bool _isPartialImport(String value) =>
      value.toLowerCase().contains('.gguf.part-');

  String _fileName(String path) => path.split(Platform.pathSeparator).last;
}
