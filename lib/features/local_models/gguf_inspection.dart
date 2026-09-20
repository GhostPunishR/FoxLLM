// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Ce qu'un fichier GGUF peut avoir de rédhibitoire.
enum GgufDefect {
  /// Les quatre premiers octets ne sont pas `GGUF`.
  notGguf,

  /// Version de format que llama.cpp ne lit pas.
  unsupportedVersion,

  /// En-tête interrompu : le fichier est tronqué ou abîmé.
  truncated,

  /// Aucun tenseur : il n'y a pas de modèle là-dedans.
  noTensors,

  /// Architecture absente, donc rien ne dit comment exécuter ce modèle.
  noArchitecture,

  /// Un tenseur à une dimension n'est pas en `f32`.
  ///
  /// C'est le défaut qui compte le plus ici, et le seul que llama.cpp ne
  /// signale pas : il charge le fichier sans rien dire, puis s'arrête net au
  /// premier message sur `binary_op: unsupported types`, un `ggml_abort` qui
  /// emporte le processus entier et ne se rattrape pas.
  ///
  /// La normalisation applique ses poids par une multiplication terme à
  /// terme, et le noyau CPU de ggml refuse d'appareiller un `f32` avec autre
  /// chose. Tous les GGUF corrects gardent donc leurs tenseurs à une
  /// dimension en `f32`, quelle que soit la quantification du reste.
  narrowTensorNotFloat32,
}

/// Verdict d'un examen de fichier GGUF.
class GgufInspection {
  const GgufInspection.valid({
    required this.architecture,
    required this.tensorCount,
  }) : defect = null,
       detail = null;

  const GgufInspection.rejected(this.defect, {this.detail})
    : architecture = null,
      tensorCount = 0;

  final GgufDefect? defect;

  /// Précision utile au message : nom du tenseur fautif, version lue.
  final String? detail;

  final String? architecture;
  final int tensorCount;

  bool get isValid => defect == null;
}

/// Types de valeurs de métadonnée, tels que GGUF les numérote.
const _typeUint8 = 0;
const _typeInt8 = 1;
const _typeUint16 = 2;
const _typeInt16 = 3;
const _typeUint32 = 4;
const _typeInt32 = 5;
const _typeFloat32 = 6;
const _typeBool = 7;
const _typeString = 8;
const _typeArray = 9;
const _typeUint64 = 10;
const _typeInt64 = 11;
const _typeFloat64 = 12;

/// Type de tenseur `f32`, tel que ggml le numérote.
const _ggmlF32 = 0;

/// Versions du format que llama.cpp sait lire.
const _supportedVersions = <int>{2, 3};

/// Un gros modèle ne doit pas être lu en entier : seul l'en-tête compte, et il
/// tient très largement là-dedans. Au-delà, le fichier est soit anormal, soit
/// hors de ce que cet examen prétend couvrir.
const _headerBudgetBytes = 64 * 1024 * 1024;

/// Examine l'en-tête d'un fichier GGUF sans le charger.
///
/// Rendu avant que le fichier rejoigne la bibliothèque : un modèle refusé ici
/// n'est jamais copié, donc jamais proposé, donc jamais chargé.
Future<GgufInspection> inspectGgufFile(File file) async {
  final handle = await file.open();
  try {
    final reader = _HeaderReader(handle, await file.length());
    return await _inspect(reader);
  } on _TruncatedHeader {
    return const GgufInspection.rejected(GgufDefect.truncated);
  } finally {
    await handle.close();
  }
}

Future<GgufInspection> _inspect(_HeaderReader reader) async {
  final magic = await reader.take(4);
  if (magic.length < 4 ||
      magic[0] != 0x47 ||
      magic[1] != 0x47 ||
      magic[2] != 0x55 ||
      magic[3] != 0x46) {
    return const GgufInspection.rejected(GgufDefect.notGguf);
  }

  final version = await reader.uint32();
  if (!_supportedVersions.contains(version)) {
    return GgufInspection.rejected(
      GgufDefect.unsupportedVersion,
      detail: '$version',
    );
  }

  final tensorCount = await reader.uint64();
  final metadataCount = await reader.uint64();
  if (tensorCount == 0) {
    return const GgufInspection.rejected(GgufDefect.noTensors);
  }

  String? architecture;
  for (var index = 0; index < metadataCount; index++) {
    final key = await reader.string();
    final type = await reader.uint32();
    final value = await reader.value(type);
    if (key == 'general.architecture' && value is String) {
      architecture = value;
    }
  }
  if (architecture == null || architecture.isEmpty) {
    return const GgufInspection.rejected(GgufDefect.noArchitecture);
  }

  for (var index = 0; index < tensorCount; index++) {
    final name = await reader.string();
    final dimensions = await reader.uint32();
    for (var axis = 0; axis < dimensions; axis++) {
      await reader.uint64();
    }
    final type = await reader.uint32();
    await reader.uint64(); // Décalage dans le bloc de données.

    if (dimensions == 1 && type != _ggmlF32) {
      return GgufInspection.rejected(
        GgufDefect.narrowTensorNotFloat32,
        detail: name,
      );
    }
  }

  return GgufInspection.valid(
    architecture: architecture,
    tensorCount: tensorCount,
  );
}

class _TruncatedHeader implements Exception {
  const _TruncatedHeader();
}

/// Lecture séquentielle de l'en-tête, par tranches.
///
/// Le fichier fait souvent plusieurs gigaoctets : le lire en entier pour
/// n'en garder que le début serait absurde sur un téléphone.
class _HeaderReader {
  _HeaderReader(this._handle, this._length);

  static const _chunkSize = 256 * 1024;

  final RandomAccessFile _handle;
  final int _length;

  Uint8List _buffer = Uint8List(0);
  int _offset = 0;
  int _consumed = 0;

  Future<void> _ensure(int count) async {
    if (_offset + count <= _buffer.length) {
      return;
    }
    if (_consumed + count > _headerBudgetBytes || _consumed + count > _length) {
      throw const _TruncatedHeader();
    }
    final remaining = Uint8List.sublistView(_buffer, _offset);
    final wanted = count > _chunkSize ? count : _chunkSize;
    final fresh = await _handle.read(wanted);
    if (fresh.isEmpty) {
      throw const _TruncatedHeader();
    }
    final merged = Uint8List(remaining.length + fresh.length)
      ..setAll(0, remaining)
      ..setAll(remaining.length, fresh);
    _buffer = merged;
    _offset = 0;
    if (_buffer.length < count) {
      throw const _TruncatedHeader();
    }
  }

  Future<Uint8List> take(int count) async {
    await _ensure(count);
    final slice = Uint8List.sublistView(_buffer, _offset, _offset + count);
    _offset += count;
    _consumed += count;
    return slice;
  }

  ByteData _view(Uint8List bytes) =>
      ByteData.sublistView(Uint8List.fromList(bytes));

  Future<int> uint32() async =>
      _view(await take(4)).getUint32(0, Endian.little);

  Future<int> uint64() async =>
      _view(await take(8)).getUint64(0, Endian.little);

  Future<String> string() async {
    final length = await uint64();
    // Une longueur aberrante signale un en-tête abîmé plutôt qu'un très long
    // nom : mieux vaut le dire que tenter d'allouer.
    if (length < 0 || length > _headerBudgetBytes) {
      throw const _TruncatedHeader();
    }
    return utf8.decode(await take(length), allowMalformed: true);
  }

  /// Lit une valeur de métadonnée pour la dépasser.
  ///
  /// Seule `general.architecture` est retenue ; tout le reste n'est lu que
  /// pour atteindre la table des tenseurs, qui la suit.
  Future<Object?> value(int type) async {
    switch (type) {
      case _typeUint8:
      case _typeInt8:
      case _typeBool:
        return (await take(1))[0];
      case _typeUint16:
      case _typeInt16:
        await take(2);
        return null;
      case _typeUint32:
      case _typeInt32:
      case _typeFloat32:
        await take(4);
        return null;
      case _typeUint64:
      case _typeInt64:
      case _typeFloat64:
        await take(8);
        return null;
      case _typeString:
        return string();
      case _typeArray:
        final elementType = await uint32();
        final count = await uint64();
        if (count < 0 || count > _headerBudgetBytes) {
          throw const _TruncatedHeader();
        }
        for (var index = 0; index < count; index++) {
          await value(elementType);
        }
        return null;
      default:
        // Un type inconnu rend la suite illisible : impossible de savoir
        // combien d'octets sauter.
        throw const _TruncatedHeader();
    }
  }
}

/// Refus d'un fichier GGUF à l'import.
///
/// Porte le défaut plutôt qu'un message : la phrase montrée dépend de la
/// langue, et c'est l'écran qui la connaît.
class GgufRejectedException implements Exception {
  const GgufRejectedException(this.defect, {this.detail});

  final GgufDefect defect;
  final String? detail;

  @override
  String toString() => 'GgufRejectedException(${defect.name}, $detail)';
}
