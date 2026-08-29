import 'dart:io';

import 'package:local_llm_bridge/local_llm_bridge.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/runtime_smoke_check.dart <model.gguf> [prompt]',
    );
    exitCode = 64;
    return;
  }

  final modelPath = args.first;
  final prompt = args.length > 1
      ? args.skip(1).join(' ')
      : 'Summarize this note in one concise sentence: Local inference works.';
  LocalLlmBridgeRuntime? runtime;

  try {
    final stopwatch = Stopwatch()..start();
    runtime = LocalLlmBridgeRuntime.load(modelPath);
    final output = runtime.generate(prompt);
    stopwatch.stop();
    stdout.writeln('elapsed_ms=${stopwatch.elapsedMilliseconds}');
    stdout.writeln('output=$output');
  } on LocalLlmBridgeException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    runtime?.close();
  }
}
