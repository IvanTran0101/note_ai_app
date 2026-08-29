import 'package:local_llm_bridge/local_llm_bridge_stub.dart';
import 'package:test/test.dart';

/// Tests for the Web-safe stub implementation.
///
/// The stub is imported directly (NOT through the conditional export) so this
/// test file never pulls in `dart:ffi` — it proves the stub library itself is
/// Web-compilable and that the public API surface is the same as the native
/// implementation, while deliberately rejecting native calls.
void main() {
  test('web stub exposes the same API and rejects native calls', () {
    expect(() => localLlmBridgeSmokeVersion(), throwsUnsupportedError);
    expect(() => localLlmBridgeSmokeEcho(1), throwsUnsupportedError);
    expect(
      () => LocalLlmBridgeRuntime.load('model.gguf'),
      throwsUnsupportedError,
    );
  });
}
