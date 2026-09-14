/// Native (dart:ffi) implementation of the `local_llm_bridge` API.
///
/// This library is only ever imported on platforms where `dart:ffi` exists
/// (see the conditional export in `local_llm_bridge.dart`).
library;

import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import 'local_llm_bridge_bindings_generated.dart' as bindings;

const int _errorCapacity = 1024;
const int _initialOutputCapacity = 64 * 1024;
final int _ok =
    bindings.local_llm_bridge_status.LOCAL_LLM_BRIDGE_STATUS_OK.value;
final int _outputTooSmall = bindings
    .local_llm_bridge_status
    .LOCAL_LLM_BRIDGE_STATUS_OUTPUT_TOO_SMALL
    .value;

/// An error returned by the native runtime facade.
final class LocalLlmBridgeException implements Exception {
  LocalLlmBridgeException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => 'LocalLlmBridgeException($status): $message';
}

/// A model-backed, CPU-only llama.cpp runtime.
///
/// The handle owns the native model and context. Call [close] when the runtime
/// is no longer needed. Requests are synchronous in this slice; the future
/// isolate/streaming adapter will sit above this boundary.
final class LocalLlmBridgeRuntime {
  LocalLlmBridgeRuntime._(this._handle);

  ffi.Pointer<ffi.Void> _handle;
  bool _closed = false;

  /// Loads a GGUF model from [modelPath].
  ///
  /// A zero [contextSize] or [threads] delegates to the native low-tier
  /// defaults. The runtime starts with CPU-only execution.
  static LocalLlmBridgeRuntime load(
    String modelPath, {
    int contextSize = 2048,
    int threads = 0,
  }) {
    final nativeModelPath = modelPath.toNativeUtf8();
    final status = calloc<ffi.Int32>();
    final errorBuffer = calloc<ffi.Char>(_errorCapacity);
    try {
      final handle = bindings.local_llm_bridge_runtime_create(
        nativeModelPath.cast<ffi.Char>(),
        contextSize,
        threads,
        status,
        errorBuffer,
        _errorCapacity,
      );
      if (handle == ffi.nullptr) {
        throw LocalLlmBridgeException(
          status.value,
          _readError(errorBuffer, 'llama.cpp could not load the model'),
        );
      }
      return LocalLlmBridgeRuntime._(handle);
    } finally {
      malloc.free(nativeModelPath);
      calloc.free(status);
      calloc.free(errorBuffer);
    }
  }

  /// Whether [close] has already released the native resources.
  bool get isClosed => _closed;

  /// Generates a complete response with deterministic greedy sampling.
  String generate(String prompt, {int maxTokens = 128}) {
    _ensureOpen();
    final nativePrompt = prompt.toNativeUtf8();
    try {
      return _runNativeGeneration(
        (outputBuffer, outputCapacity, outputLength, errorBuffer) =>
            bindings.local_llm_bridge_runtime_generate(
          _handle,
          nativePrompt.cast<ffi.Char>(),
          maxTokens,
          outputBuffer,
          outputCapacity,
          outputLength,
          errorBuffer,
          _errorCapacity,
        ),
      );
    } finally {
      malloc.free(nativePrompt);
    }
  }

  /// Generates a complete chat response with deterministic greedy sampling.
  ///
  /// The native side formats [systemPrompt] and [userPrompt] with the model's
  /// `tokenizer.chat_template` through llama.cpp's modern Jinja/PEG chat
  /// layer, including the template-specific assistant generation prompt. If
  /// [systemPrompt] is empty, only a user turn is formatted. No template is
  /// hardcoded here; models without a usable chat template fail with a
  /// [LocalLlmBridgeException].
  String generateChat(
    String systemPrompt,
    String userPrompt, {
    int maxTokens = 128,
  }) {
    _ensureOpen();
    final nativeSystemPrompt = systemPrompt.toNativeUtf8();
    final nativeUserPrompt = userPrompt.toNativeUtf8();
    try {
      return _runNativeGeneration(
        (outputBuffer, outputCapacity, outputLength, errorBuffer) =>
            bindings.local_llm_bridge_runtime_generate_chat(
          _handle,
          nativeSystemPrompt.cast<ffi.Char>(),
          nativeUserPrompt.cast<ffi.Char>(),
          maxTokens,
          outputBuffer,
          outputCapacity,
          outputLength,
          errorBuffer,
          _errorCapacity,
        ),
      );
    } finally {
      malloc.free(nativeSystemPrompt);
      malloc.free(nativeUserPrompt);
    }
  }

  /// Releases the native model and context. Safe to call more than once.
  void close() {
    if (_closed) {
      return;
    }
    bindings.local_llm_bridge_runtime_free(_handle);
    _handle = ffi.nullptr;
    _closed = true;
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('local_llm_bridge: runtime is already closed');
    }
  }
}

/// Runs one native generation call, retrying with a larger output buffer when
/// the native side reports OUTPUT_TOO_SMALL.
String _runNativeGeneration(
  int Function(
    ffi.Pointer<ffi.Char> outputBuffer,
    int outputCapacity,
    ffi.Pointer<ffi.Int32> outputLength,
    ffi.Pointer<ffi.Char> errorBuffer,
  ) run,
) {
  var outputCapacity = _initialOutputCapacity;
  for (var attempt = 0; attempt < 3; attempt++) {
    final outputBuffer = malloc<ffi.Char>(outputCapacity);
    final outputLength = calloc<ffi.Int32>();
    final errorBuffer = calloc<ffi.Char>(_errorCapacity);
    try {
      final status =
          run(outputBuffer, outputCapacity, outputLength, errorBuffer);
      if (status == _outputTooSmall) {
        final required = outputLength.value;
        if (required < 0 || required >= 0x7fffffff) {
          throw LocalLlmBridgeException(
            status,
            'native runtime returned an invalid output size: $required',
          );
        }
        outputCapacity = required + 1;
        continue;
      }
      if (status != _ok) {
        throw LocalLlmBridgeException(
          status,
          _readError(errorBuffer, 'llama.cpp generation failed'),
        );
      }

      final length = outputLength.value;
      if (length < 0 || length >= outputCapacity) {
        throw LocalLlmBridgeException(
          status,
          'native runtime returned an invalid output length: $length',
        );
      }
      return outputBuffer.cast<Utf8>().toDartString(length: length);
    } finally {
      malloc.free(outputBuffer);
      calloc.free(outputLength);
      calloc.free(errorBuffer);
    }
  }

  throw LocalLlmBridgeException(
    _outputTooSmall,
    'native runtime output exceeded the retry limit',
  );
}

String _readError(ffi.Pointer<ffi.Char> buffer, String fallback) {
  final bytes = buffer.cast<ffi.Uint8>().asTypedList(_errorCapacity);
  var length = 0;
  while (length < bytes.length && bytes[length] != 0) {
    length++;
  }
  final message = utf8.decode(bytes.sublist(0, length), allowMalformed: true);
  return message.isEmpty ? fallback : message;
}

/// Returns the native smoke-ABI version string, e.g.
/// `local_llm_bridge 0.0.1-smoke (C ABI)`.
///
/// This is a smoke-only API for the first implementation slice: it proves the
/// Dart FFI boundary, the C ABI facade, and the native build hook are wired
/// end to end. It is NOT llama.cpp inference and does not load any model.
///
/// The string is written into a Dart-allocated buffer by the C side (see
/// `local_llm_bridge_smoke_version` in `src/local_llm_bridge.h`); the buffer
/// is malloc'd and freed entirely on the Dart side, so ownership never
/// crosses the ABI boundary and there is nothing to leak.
String localLlmBridgeSmokeVersion() {
  // Size query: ask the native side how large the buffer must be (NUL
  // terminator included).
  final int required = bindings.local_llm_bridge_smoke_version(ffi.nullptr, 0);
  if (required <= 0) {
    throw StateError(
      'local_llm_bridge: native smoke version returned invalid size '
      '$required',
    );
  }
  final ffi.Pointer<ffi.Uint8> buffer = malloc<ffi.Uint8>(required);
  try {
    final int written = bindings.local_llm_bridge_smoke_version(
      buffer.cast<ffi.Char>(),
      required,
    );
    if (written < 0 || written >= required) {
      throw StateError(
        'local_llm_bridge: native smoke version wrote $written bytes '
        'into a $required-byte buffer',
      );
    }
    return buffer.cast<Utf8>().toDartString(length: written);
  } finally {
    malloc.free(buffer);
  }
}

/// Echoes an integer through the C ABI boundary (Dart -> C -> Dart).
///
/// Smoke-only: validates bidirectional argument/return plumbing, nothing more.
int localLlmBridgeSmokeEcho(int value) =>
    bindings.local_llm_bridge_smoke_echo(value);
