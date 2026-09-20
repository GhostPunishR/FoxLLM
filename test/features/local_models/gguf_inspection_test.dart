// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:foxllm/features/local_models/gguf_inspection.dart';

/// L'examen d'un GGUF avant son import.
///
/// Il existe pour un défaut précis et vécu : un poids de normalisation en
/// `f16` au lieu de `f32` se charge sans erreur, puis tue le processus au
/// premier message sur un `ggml_abort` qui ne se rattrape pas. Comme
/// l'application laisse importer n'importe quel fichier, ce cas suffisait à
/// faire tomber FoxLLM sans un mot.
void main() {
  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('foxllm-gguf-');
  });
  tearDown(() async {
    if (workspace.existsSync()) {
      await workspace.delete(recursive: true);
    }
  });

  Future<File> write(List<int> bytes, [String name = 'model.gguf']) async {
    final file = File('${workspace.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  test('un modèle bien formé passe', () async {
    final result = await inspectGgufFile(
      await write(
        _gguf(tensors: <_Tensor>[_Tensor('output_norm.weight', 1, 0)]),
      ),
    );

    expect(result.isValid, isTrue);
    expect(result.architecture, 'llama');
    expect(result.tensorCount, 1);
  });

  test('un tenseur à une dimension en f16 est refusé', () async {
    // Le cas exact du plantage : llama.cpp charge, puis s'arrête net.
    final result = await inspectGgufFile(
      await write(
        _gguf(tensors: <_Tensor>[_Tensor('blk.0.attn_norm.weight', 1, 1)]),
      ),
    );

    expect(result.isValid, isFalse);
    expect(result.defect, GgufDefect.narrowTensorNotFloat32);
    expect(result.detail, 'blk.0.attn_norm.weight');
  });

  test('un tenseur à deux dimensions peut être quantifié', () async {
    // C'est tout l'intérêt du format : seuls les tenseurs à une dimension
    // sont contraints. Refuser les autres interdirait toute quantification.
    final result = await inspectGgufFile(
      await write(
        _gguf(tensors: <_Tensor>[_Tensor('token_embd.weight', 2, 8)]),
      ),
    );

    expect(result.isValid, isTrue);
  });

  test('un fichier qui n’est pas du GGUF est refusé', () async {
    final result = await inspectGgufFile(
      await write(utf8.encode('ceci est un texte, pas un modèle')),
    );

    expect(result.defect, GgufDefect.notGguf);
  });

  test('une version inconnue est refusée, et nommée', () async {
    final result = await inspectGgufFile(await write(_gguf(version: 9)));

    expect(result.defect, GgufDefect.unsupportedVersion);
    expect(result.detail, '9');
  });

  test('un fichier sans tenseur est refusé', () async {
    final result = await inspectGgufFile(
      await write(_gguf(tensors: const <_Tensor>[])),
    );

    expect(result.defect, GgufDefect.noTensors);
  });

  test('un fichier sans architecture est refusé', () async {
    final result = await inspectGgufFile(
      await write(_gguf(architecture: null)),
    );

    expect(result.defect, GgufDefect.noArchitecture);
  });

  test('un en-tête coupé est refusé plutôt que deviné', () async {
    final whole = _gguf();
    final result = await inspectGgufFile(
      await write(whole.sublist(0, whole.length - 12)),
    );

    expect(result.defect, GgufDefect.truncated);
  });

  test('un fichier vide est refusé', () async {
    expect((await inspectGgufFile(await write(<int>[]))).isValid, isFalse);
  });

  test('l’examen ne lit pas le corps du fichier', () async {
    // Un modèle pèse des gigaoctets : l'examen doit rester sur l'en-tête,
    // sinon l'import deviendrait plus lent que la copie elle-même.
    final header = _gguf();
    final padded = <int>[...header, ...List<int>.filled(4 * 1024 * 1024, 0)];
    final file = await write(padded, 'gros.gguf');

    final stopwatch = Stopwatch()..start();
    final result = await inspectGgufFile(file);
    stopwatch.stop();

    expect(result.isValid, isTrue);
    expect(stopwatch.elapsedMilliseconds, lessThan(500));
  });
}

class _Tensor {
  const _Tensor(this.name, this.dimensions, this.type);

  final String name;
  final int dimensions;

  /// Numérotation ggml : 0 vaut `f32`, 1 vaut `f16`.
  final int type;
}

/// Fabrique un GGUF minimal mais conforme.
///
/// Écrit en Dart plutôt que produit par un outil : le banc reste autonome, et
/// chaque octet malformé est posé exprès, à l'endroit voulu.
Uint8List _gguf({
  int version = 3,
  String? architecture = 'llama',
  List<_Tensor> tensors = const <_Tensor>[_Tensor('output_norm.weight', 1, 0)],
}) {
  final out = BytesBuilder();
  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    out.add(data.buffer.asUint8List());
  }

  void u64(int value) {
    final data = ByteData(8)..setUint64(0, value, Endian.little);
    out.add(data.buffer.asUint8List());
  }

  void str(String value) {
    final bytes = utf8.encode(value);
    u64(bytes.length);
    out.add(bytes);
  }

  out.add(utf8.encode('GGUF'));
  u32(version);
  u64(tensors.length);
  u64(architecture == null ? 0 : 1);

  if (architecture != null) {
    str('general.architecture');
    u32(8); // Type chaîne.
    str(architecture);
  }

  for (final tensor in tensors) {
    str(tensor.name);
    u32(tensor.dimensions);
    for (var axis = 0; axis < tensor.dimensions; axis++) {
      u64(4);
    }
    u32(tensor.type);
    u64(0);
  }

  return out.toBytes();
}
