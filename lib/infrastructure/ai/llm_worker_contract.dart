/// Platform-neutral contract for the long-lived LLM worker client.
///
/// This library must stay free of `dart:ffi` and `dart:io` so it compiles on
/// the Web. The native/isolate implementation lives behind a conditional
/// import in `llm_worker_client.dart`; on Web the stub's [generateChat]
/// throws [UnsupportedError] — Web never fakes a summary.
library;

/// A client bound to one long-lived worker isolate that owns the native
/// llama.cpp runtime.
///
/// Requests are serializable (JSON-safe maps with request IDs); the native
/// runtime handle never crosses the isolate boundary. Implementations must
/// report startup failure, fail pending futures if the worker exits, shut
/// down in order, and fail fast after [dispose].
abstract interface class LlmWorkerClient {
  /// Sends one chat generation request to the worker and returns the raw
  /// generated text.
  ///
  /// May throw synchronously (client disposed / worker stopped) or fail the
  /// returned future (native error, worker exit).
  Future<String> generateChat({
    required String systemPrompt,
    required String userPrompt,
    int maxTokens = 128,
  });

  /// Shuts the worker down in order (after in-flight requests) and releases
  /// resources. Safe to call more than once.
  Future<void> dispose();
}

/// An error raised by the worker client: spawn/startup failure, a native
/// runtime error, or unexpected worker exit.
final class LlmWorkerException implements Exception {
  const LlmWorkerException(this.message);

  final String message;

  @override
  String toString() => 'LlmWorkerException: $message';
}
