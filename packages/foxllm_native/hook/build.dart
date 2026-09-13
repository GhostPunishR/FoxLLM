// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final code = input.config.code;
    final isAndroidArm64 =
        code.targetOS == OS.android &&
        code.targetArchitecture == Architecture.arm64;

    if (!isAndroidArm64) {
      final builder = CBuilder.library(
        name: input.packageName,
        assetName: 'foxllm_native.dart',
        language: Language.cpp,
        std: 'c++17',
        sources: const <String>['src/foxllm_native.cpp'],
        includes: const <String>['src'],
      );

      await builder.run(input: input, output: output);
      return;
    }

    hierarchicalLoggingEnabled = true;
    final logger = Logger('foxllm_native.cmake')
      ..level = Level.ALL
      ..onRecord.listen((record) => stderr.writeln(record.message));

    final installDirectory = input.outputDirectory.resolve('install/');
    final builder = CMakeBuilder.create(
      name: input.packageName,
      sourceDir: input.packageRoot,
      defines: <String, String?>{
        'CMAKE_BUILD_TYPE': 'Release',
        'CMAKE_INSTALL_PREFIX': installDirectory.toFilePath(),
        'FOXLLM_WITH_LLAMA_CPP': 'ON',
      },
      targets: const <String>['install'],
      parallelUseAllProcessors: true,
      logger: logger,
    );

    await builder.run(input: input, output: output, logger: logger);

    final library = installDirectory.resolve('lib/libfoxllm_native.so');
    if (!File.fromUri(library).existsSync()) {
      throw StateError('CMake did not produce ${library.toFilePath()}.');
    }

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'foxllm_native.dart',
        linkMode: DynamicLoadingBundled(),
        file: library,
      ),
    );
  });
}
