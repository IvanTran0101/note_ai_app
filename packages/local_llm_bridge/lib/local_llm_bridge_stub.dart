/// Web-safe stub for the `local_llm_bridge` package.
///
/// `dart:ffi` and native assets are unavailable on the Web, so this library
/// exposes the same public API as `local_llm_bridge_io` but never performs
/// local inference: every function throws [UnsupportedError]. The Web build of
/// the app must use a separate remote inference path (future work).
///
/// This stub deliberately contains no fake LLM behavior and no `dart:ffi`
/// import, keeping the public entrypoint compilable on the Web.
library;

/// An error type kept for API parity with the native implementation.
final class LocalLlmBridgeException implements Exception {
  LocalLlmBridgeException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => 'LocalLlmBridgeException($status): $message';
}

/// Web does not load local GGUF models in this package.
final class LocalLlmBridgeRuntime {
  LocalLlmBridgeRuntime._();

  static LocalLlmBridgeRuntime load(
    String modelPath, {
    int contextSize = 2048,
    int threads = 0,
  }) {
    throw UnsupportedError(
      'local_llm_bridge: local llama.cpp inference is not available on Web. '
      'Use the remote inference path.',
    );
  }

  bool get isClosed => true;

  String generate(String prompt, {int maxTokens = 128}) {
    throw UnsupportedError(
      'local_llm_bridge: local llama.cpp inference is not available on Web.',
    );
  }

  void close() {}
}

/// Throws [UnsupportedError]: the native smoke ABI is not available on Web.
///
/// No local inference happens on the Web.
String localLlmBridgeSmokeVersion() {
  throw UnsupportedError(
    'local_llm_bridge: the native smoke API is not available on the Web. '
    'No local inference is performed on Web; use a remote inference path.',
  );
}

/// Throws [UnsupportedError]: the native smoke ABI is not available on Web.
int localLlmBridgeSmokeEcho(int value) {
  throw UnsupportedError(
    'local_llm_bridge: the native smoke API is not available on the Web.',
  );
}
