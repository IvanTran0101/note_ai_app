import 'package:local_llm_bridge/local_llm_bridge.dart';
import 'package:local_llm_bridge/local_llm_bridge_bindings_generated.dart'
    as bindings;
import 'package:test/test.dart';

/// Smoke-API tests against the REAL native C ABI facade.
///
/// On VM/desktop platforms (this test runner) `local_llm_bridge.dart`
/// resolves to the dart:ffi implementation and these tests exercise the
/// native asset built by `hook/build.dart`. There is no fake LLM behavior and
/// no model involved.
void main() {
  test('smoke version comes from the native C ABI', () {
    final String version = localLlmBridgeSmokeVersion();

    expect(version, isNotEmpty);
    expect(version, contains('local_llm_bridge'));
    expect(version, contains('smoke'));
    // The version string must NOT overclaim llama.cpp/model support.
    expect(version.toLowerCase(), isNot(contains('llama')));
    expect(version.toLowerCase(), isNot(contains('model')));
  });

  test('smoke echo round-trips through the C ABI', () {
    expect(localLlmBridgeSmokeEcho(42), 42);
    expect(localLlmBridgeSmokeEcho(-7), -7);
    expect(localLlmBridgeSmokeEcho(0), 0);
  });

  test('runtime rejects an invalid context before loading a model', () {
    try {
      LocalLlmBridgeRuntime.load('not-used.gguf', contextSize: 1);
      fail('expected an invalid-argument error');
    } on LocalLlmBridgeException catch (error) {
      expect(error.status, 1);
      expect(error.message, contains('context size'));
    }
  });

  test('runtime reports a missing GGUF model', () {
    try {
      LocalLlmBridgeRuntime.load(
        '/private/tmp/local_llm_bridge_missing_model_8ccc5cd1.gguf',
      );
      fail('expected a model-load error');
    } on LocalLlmBridgeException catch (error) {
      expect(error.status, 2);
      expect(error.message, contains('GGUF'));
    }
  });

  test('chat ABI surface is present in the generated bindings', () {
    // A runtime cannot be created without a real GGUF model, so this suite
    // proves the regenerated ABI surface instead: the new status codes and
    // the generate_chat external must exist after `dart run ffigen`. The full
    // chat path is exercised by tool/runtime_smoke_check.dart with a model.
    expect(
      bindings.local_llm_bridge_status
          .LOCAL_LLM_BRIDGE_STATUS_CHAT_TEMPLATE_MISSING
          .value,
      8,
    );
    expect(
      bindings
          .local_llm_bridge_status
          .LOCAL_LLM_BRIDGE_STATUS_CHAT_TEMPLATE_FAILED
          .value,
      9,
    );
    expect(bindings.local_llm_bridge_runtime_generate_chat, isA<Function>());
  });
}
