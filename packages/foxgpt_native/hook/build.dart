import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final builder = CBuilder.library(
      name: input.packageName,
      assetName: 'foxgpt_native.dart',
      language: Language.cpp,
      std: 'c++17',
      sources: const <String>[
        'src/foxgpt_native.cpp',
      ],
      includes: const <String>[
        'src',
      ],
    );

    await builder.run(input: input, output: output);
  });
}
