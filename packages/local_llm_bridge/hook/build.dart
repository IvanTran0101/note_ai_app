// Build-hook logs must be forwarded to the hook process output.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

const _llamaRoot = 'third_party/llama.cpp-0.3.0';
const _ggmlCArchiveName = 'local_llm_bridge_ggml_c';
const _ggmlVersion = '0.22.0';
const _llamaVersion = '0.3.0';
const _llamaCommit = 'c1d0e7a004015f23bc0233470b747b596f29b264';

List<String> _directSources(
  Uri packageRoot,
  String relativeDirectory,
  String extension,
) {
  final directory = Directory.fromUri(
    packageRoot.resolve('$relativeDirectory/'),
  );
  if (!directory.existsSync()) {
    throw StateError('Required native source directory is missing: $directory');
  }

  final sources =
      directory
          .listSync(followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith(extension))
          .map((file) => '$relativeDirectory/${file.uri.pathSegments.last}')
          .toList()
        ..sort();
  if (sources.isEmpty) {
    throw StateError('No $extension sources found in $directory');
  }
  return sources;
}

List<String> _cpuArchitectureSources(Architecture? architecture) {
  if (architecture == Architecture.arm || architecture == Architecture.arm64) {
    return const [
      '$_llamaRoot/ggml/src/ggml-cpu/arch/arm/quants.c',
      '$_llamaRoot/ggml/src/ggml-cpu/arch/arm/repack.cpp',
    ];
  }
  if (architecture == Architecture.ia32 || architecture == Architecture.x64) {
    return const [
      '$_llamaRoot/ggml/src/ggml-cpu/arch/x86/quants.c',
      '$_llamaRoot/ggml/src/ggml-cpu/arch/x86/repack.cpp',
    ];
  }
  throw UnsupportedError(
    'local_llm_bridge supports ARM and x86 native builds; '
    'received ${architecture?.name ?? 'unknown'}',
  );
}

List<String> _nativeIncludes() => const [
  'src',
  _llamaRoot,
  '$_llamaRoot/include',
  '$_llamaRoot/common',
  '$_llamaRoot/vendor',
  '$_llamaRoot/vendor/nlohmann',
  '$_llamaRoot/vendor/sheredom',
  '$_llamaRoot/ggml/include',
  '$_llamaRoot/ggml/src',
  '$_llamaRoot/ggml/src/ggml-cpu',
  '$_llamaRoot/src',
];

/// Modern llama.cpp chat-template support. The legacy public
/// `llama_chat_apply_template` API is intentionally not used for the bridge:
/// it only recognizes a fixed list of templates and cannot render the
/// Gemma 4 Jinja/PEG template embedded in the GGUF metadata.
List<String> _commonChatSources() => const [
  '$_llamaRoot/common/chat.cpp',
  '$_llamaRoot/common/chat-auto-parser-generator.cpp',
  '$_llamaRoot/common/chat-auto-parser-helpers.cpp',
  '$_llamaRoot/common/chat-diff-analyzer.cpp',
  '$_llamaRoot/common/chat-peg-parser.cpp',
  '$_llamaRoot/common/json-schema-to-grammar.cpp',
  '$_llamaRoot/common/json.cpp',
  '$_llamaRoot/common/log.cpp',
  '$_llamaRoot/common/peg-parser.cpp',
  '$_llamaRoot/common/trie.cpp',
  '$_llamaRoot/common/unicode.cpp',
  '$_llamaRoot/common/jinja/caps.cpp',
  '$_llamaRoot/common/jinja/lexer.cpp',
  '$_llamaRoot/common/jinja/parser.cpp',
  '$_llamaRoot/common/jinja/runtime.cpp',
  '$_llamaRoot/common/jinja/string.cpp',
  '$_llamaRoot/common/jinja/value.cpp',
];

List<String> _ggmlCSources(Architecture? architecture) => [
  '$_llamaRoot/ggml/src/ggml.c',
  '$_llamaRoot/ggml/src/ggml-alloc.c',
  '$_llamaRoot/ggml/src/ggml-quants.c',
  '$_llamaRoot/ggml/src/ggml-cpu/ggml-cpu.c',
  '$_llamaRoot/ggml/src/ggml-cpu/quants.c',
  for (final source in _cpuArchitectureSources(architecture))
    if (source.endsWith('.c')) source,
];

List<String> _llamaCppSources(Uri packageRoot, Architecture? architecture) => [
  'src/local_llm_bridge.cpp',
  ..._commonChatSources(),
  ..._directSources(packageRoot, '$_llamaRoot/ggml/src', '.cpp'),
  ..._directSources(packageRoot, '$_llamaRoot/ggml/src/ggml-cpu', '.cpp'),
  for (final source in _cpuArchitectureSources(architecture))
    if (source.endsWith('.cpp')) source,
  ..._directSources(packageRoot, '$_llamaRoot/src', '.cpp'),
  ..._directSources(packageRoot, '$_llamaRoot/src/models', '.cpp'),
];

const Map<String, String?> _baseNativeDefines = {
  'GGML_VERSION': '"$_ggmlVersion"',
  'GGML_COMMIT': '"$_llamaCommit"',
  'GGML_SCHED_MAX_COPIES': '4',
  'GGML_USE_CPU': null,
  'LLAMA_VERSION': '"$_llamaVersion"',
  'LLAMA_COMMIT': '"$_llamaCommit"',
};

/// Mirrors llama.cpp/ggml's POSIX feature-test definitions.
///
/// The upstream CMake build enables these definitions before compiling the
/// C/C++ ggml targets. Without them, a strict Linux `-std=c11` build hides
/// declarations for `getline`, `posix_memalign`, and `M_PI`, even though the
/// same sources compile with the platform defaults on macOS.
Map<String, String?> _nativeDefines(OS targetOS) => {
  ..._baseNativeDefines,
  if (targetOS == OS.linux || targetOS == OS.android) ...{
    '_XOPEN_SOURCE': '600',
    '_GNU_SOURCE': null,
  },
  if (targetOS == OS.macOS || targetOS == OS.iOS) ...{
    '_XOPEN_SOURCE': '600',
    '_DARWIN_C_SOURCE': null,
  },
};

List<String> _threadFlags(OS targetOS) =>
    targetOS == OS.android || targetOS == OS.linux
    ? const ['-pthread']
    : const [];

List<String> _systemLibraries(OS targetOS) => switch (targetOS) {
  OS.android => const ['dl'],
  OS.linux => const ['dl', 'm'],
  _ => const [],
};

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final llamaHeader = File.fromUri(
      input.packageRoot.resolve('$_llamaRoot/include/llama.h'),
    );
    if (!llamaHeader.existsSync()) {
      throw StateError(
        'llama.cpp $_llamaVersion is missing. Expected: $llamaHeader',
      );
    }

    final architecture = input.config.code.targetArchitecture;
    final includes = _nativeIncludes();
    final defines = _nativeDefines(input.config.code.targetOS);
    final flags = _threadFlags(input.config.code.targetOS);

    final ggmlCBuilder = CBuilder.library(
      name: _ggmlCArchiveName,
      sources: _ggmlCSources(architecture),
      includes: includes,
      defines: defines,
      flags: flags,
      language: Language.c,
      std: 'c11',
      linkModePreference: LinkModePreference.static,
      optimizationLevel: OptimizationLevel.o3,
    );
    await ggmlCBuilder.run(
      input: input,
      output: output,
      routing: const [],
      logger: _logger(),
      linkModePreference: LinkModePreference.static,
    );

    final bridgeBuilder = CBuilder.library(
      name: input.packageName,
      assetName: '${input.packageName}_bindings_generated.dart',
      sources: _llamaCppSources(input.packageRoot, architecture),
      includes: includes,
      defines: defines,
      flags: flags,
      libraries: [
        _ggmlCArchiveName,
        ..._systemLibraries(input.config.code.targetOS),
      ],
      libraryDirectories: const ['.'],
      language: Language.cpp,
      std: 'c++17',
      cppLinkStdLib: input.config.code.targetOS == OS.android
          ? 'c++_static'
          : null,
      linkModePreference: LinkModePreference.dynamic,
      optimizationLevel: OptimizationLevel.o3,
    );
    await bridgeBuilder.run(
      input: input,
      output: output,
      routing: const [ToAppBundle()],
      logger: _logger(),
      linkModePreference: LinkModePreference.dynamic,
    );
  });
}

Logger _logger() => Logger('')
  ..level = Level.ALL
  ..onRecord.listen((record) => print(record.message));
