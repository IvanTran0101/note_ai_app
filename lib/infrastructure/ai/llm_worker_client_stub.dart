/// Web-safe unavailable implementation of [LlmWorkerClient].
///
/// `dart:io` (and therefore the worker isolate) is unavailable on the Web.
/// [startLlmWorkerClient] returns an [UnavailableLlmWorkerClient] so the app
/// can start; every [generateChat] call throws [UnsupportedError]. There is
/// deliberately NO fake summary behavior on the Web.
library;

import 'llm_worker_contract.dart';

/// A client that is never usable: the platform has no local llama.cpp runtime.
final class UnavailableLlmWorkerClient implements LlmWorkerClient {
  const UnavailableLlmWorkerClient();

  @override
  Future<String> generateChat({
    required String systemPrompt,
    required String userPrompt,
    int maxTokens = 128,
  }) {
    throw UnsupportedError(
      'Local LLM inference is not available on this platform (Web). '
      'Use a separate remote inference path.',
    );
  }

  @override
  Future<void> dispose() async {}
}

/// Returns an [UnavailableLlmWorkerClient] on platforms without an
/// isolate-backed worker (Web).
Future<LlmWorkerClient> startLlmWorkerClient({
  required String modelPath,
  int contextSize = 2048,
  int threads = 0,
}) async {
  return const UnavailableLlmWorkerClient();
}
