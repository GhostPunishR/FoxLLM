// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foxllm/features/local_models/local_model_file.dart';
import 'package:foxllm/features/local_models/local_model_library.dart';

void main() {
  late Directory tempDirectory;
  late LocalModelLibrary library;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('foxllm-models-');
    library = LocalModelLibrary(
      applicationSupportDirectory: () async => tempDirectory,
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('imports a GGUF and lists it from app storage', () async {
    final imported = await library.importModel(
      fileName: 'tiny.gguf',
      bytes: Stream<List<int>>.fromIterable(<List<int>>[
        <int>[1, 2],
        <int>[3, 4],
      ]),
      expectedSizeBytes: 4,
    );

    expect(imported.fileName, 'tiny.gguf');
    expect(imported.sizeBytes, 4);
    expect(await File(imported.path).readAsBytes(), <int>[1, 2, 3, 4]);

    final models = await library.listModels();
    expect(models, hasLength(1));
    expect(models.single.fileName, 'tiny.gguf');
  });

  test('keeps duplicate file names without overwriting', () async {
    Future<void> importOnce(List<int> bytes) async {
      await library.importModel(
        fileName: 'model.gguf',
        bytes: Stream<List<int>>.value(bytes),
        expectedSizeBytes: bytes.length,
      );
    }

    await importOnce(<int>[1]);
    await importOnce(<int>[2]);

    final models = await library.listModels();
    expect(models.map((model) => model.fileName), <String>[
      'model (2).gguf',
      'model.gguf',
    ]);
    expect(await File(models[0].path).readAsBytes(), <int>[2]);
    expect(await File(models[1].path).readAsBytes(), <int>[1]);
  });

  test(
    'keeps both models when the same name is imported concurrently',
    () async {
      // Les deux imports résolvent leur destination en parallèle : sans
      // réservation, ils visaient le même `model.gguf` et le second `rename()`
      // écrasait silencieusement le modèle du premier.
      final imported = await Future.wait<LocalModelFile>(
        <Future<LocalModelFile>>[
          library.importModel(
            fileName: 'model.gguf',
            bytes: Stream<List<int>>.value(<int>[1]),
            expectedSizeBytes: 1,
          ),
          library.importModel(
            fileName: 'model.gguf',
            bytes: Stream<List<int>>.value(<int>[2]),
            expectedSizeBytes: 1,
          ),
        ],
      );

      expect(imported.map((model) => model.path).toSet(), hasLength(2));

      final models = await library.listModels();
      expect(models.map((model) => model.fileName), <String>[
        'model (2).gguf',
        'model.gguf',
      ]);

      final contents = <int>[];
      for (final model in models) {
        contents.addAll(await File(model.path).readAsBytes());
      }
      expect(contents..sort(), <int>[1, 2]);
    },
  );

  test('frees a reserved name once the import fails', () async {
    await expectLater(
      library.importModel(
        fileName: 'retry.gguf',
        bytes: Stream<List<int>>.error(StateError('copy interrupted')),
        expectedSizeBytes: 1,
      ),
      throwsA(isA<StateError>()),
    );

    // La destination échouée doit redevenir disponible, sans suffixe « (2) ».
    final retried = await library.importModel(
      fileName: 'retry.gguf',
      bytes: Stream<List<int>>.value(<int>[5]),
      expectedSizeBytes: 1,
    );
    expect(retried.fileName, 'retry.gguf');
  });

  test('rejects non-GGUF files', () async {
    await expectLater(
      library.importModel(
        fileName: 'notes.txt',
        bytes: Stream<List<int>>.value(<int>[1]),
        expectedSizeBytes: 1,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('removes partial files after an interrupted import', () async {
    final controller = StreamController<List<int>>();
    final importFuture = library.importModel(
      fileName: 'broken.gguf',
      bytes: controller.stream,
      expectedSizeBytes: 4,
    );

    controller.add(<int>[1, 2]);
    controller.addError(StateError('copy interrupted'));
    await controller.close();

    await expectLater(importFuture, throwsA(isA<StateError>()));

    final modelsDirectory = Directory(
      '${tempDirectory.path}${Platform.pathSeparator}models',
    );
    final entries = await modelsDirectory.list().toList();
    expect(entries, isEmpty);
  });

  test('cleans stale partial imports discovered on startup', () async {
    final modelsDirectory = Directory(
      '${tempDirectory.path}${Platform.pathSeparator}models',
    );
    await modelsDirectory.create(recursive: true);
    final stale = File(
      '${modelsDirectory.path}${Platform.pathSeparator}orphan.gguf.part-123',
    );
    await stale.writeAsBytes(<int>[1, 2, 3]);

    expect(await library.listModels(), isEmpty);
    expect(await stale.exists(), isFalse);
  });

  test('does not delete a partial import that is still active', () async {
    final controller = StreamController<List<int>>();
    final firstWrite = Completer<void>();
    final importFuture = library.importModel(
      fileName: 'active.gguf',
      bytes: controller.stream,
      expectedSizeBytes: 1,
      onProgress: (_, _) {
        if (!firstWrite.isCompleted) {
          firstWrite.complete();
        }
      },
    );

    controller.add(<int>[9]);
    await firstWrite.future;

    expect(await library.listModels(), isEmpty);
    final modelsDirectory = Directory(
      '${tempDirectory.path}${Platform.pathSeparator}models',
    );
    expect(
      await modelsDirectory
          .list()
          .where((entity) => entity.path.contains('.gguf.part-'))
          .length,
      1,
    );

    await controller.close();
    final imported = await importFuture;
    expect(await File(imported.path).readAsBytes(), <int>[9]);
  });

  test('deletes an imported managed model', () async {
    final model = await library.importModel(
      fileName: 'delete-me.gguf',
      bytes: Stream<List<int>>.value(<int>[7, 8, 9]),
      expectedSizeBytes: 3,
    );

    await library.deleteModel(model);

    expect(await File(model.path).exists(), isFalse);
    expect(await library.listModels(), isEmpty);
  });
}
