import 'dart:io';

import 'package:local_llm_bridge/local_llm_bridge.dart';

// Runs one model-backed smoke request against the real native asset.
//
// Usage:
//   dart run tool/runtime_smoke_check.dart <model.gguf> [--chat] [prompt]
//
// With `--chat`, the request goes through `generateChat` (the model's own
// chat template) instead of the raw `generate` path.
void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/runtime_smoke_check.dart <model.gguf> '
      '[--chat] [prompt]',
    );
    exitCode = 64;
    return;
  }

  final modelPath = args.first;
  var chatMode = false;
  final promptParts = <String>[];
  for (final arg in args.skip(1)) {
    if (arg == '--chat') {
      chatMode = true;
    } else {
      promptParts.add(arg);
    }
  }
  final prompt = promptParts.isEmpty
      ? 'Summarize this note in one concise sentence: Local inference works.'
      : promptParts.join(' ');
  LocalLlmBridgeRuntime? runtime;

  try {
    final stopwatch = Stopwatch()..start();
    runtime = LocalLlmBridgeRuntime.load(modelPath);
    final output = chatMode
        ? runtime.generateChat('You are a helpful assistant.', prompt)
        : runtime.generate(prompt);
    stopwatch.stop();
    stdout.writeln('mode=${chatMode ? 'chat' : 'generate'}');
    stdout.writeln('elapsed_ms=${stopwatch.elapsedMilliseconds}');
    stdout.writeln('output=$output');
  } on LocalLlmBridgeException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    runtime?.close();
  }
}
