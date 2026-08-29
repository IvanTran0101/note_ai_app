# local_llm_bridge

Isolated Dart FFI package (modern `package_ffi` / build-hooks shape) exposing a
narrow C ABI facade for on-device llama.cpp inference in the note_ai_app
project.

The package builds the pinned `llama.cpp v0.3.0` source under
`third_party/llama.cpp-0.3.0` and links a CPU-only GGUF runtime. The GGUF model
is supplied by the application at runtime and is not stored in this package.

## Getting Started

This package uses the modern Flutter
[FFI package](https://flutter.dev/to/ffi-package) shape (build hooks /
native assets), not the legacy platform-plugin shape.

## Project structure

* `src/` — Native source code. `local_llm_bridge.h` is the **only** stable
  interface between Dart and native code (a C ABI facade, wrapped in
  `extern "C"`). Dart must never see C++ classes or llama.cpp types.
* `lib/` — Dart API. `local_llm_bridge.dart` is the public entrypoint and
  conditionally exports either `local_llm_bridge_io.dart` (dart:ffi, native
  platforms) or `local_llm_bridge_stub.dart` (Web-safe, throws
  `UnsupportedError` — no local inference on Web).
* `hook/build.dart` — Build hook (native_toolchain_c) that compiles
  llama.cpp and the facade into a native code asset during `dart pub get` and
  app builds.

## Smoke API

The smoke functions remain available as a wiring check:

* `String localLlmBridgeSmokeVersion()` — returns the native C ABI version
  string, e.g. `local_llm_bridge 0.0.1-smoke (C ABI)`.
* `int localLlmBridgeSmokeEcho(int value)` — round-trips an integer through
  the ABI boundary.

On Web both throw `UnsupportedError`.

## Runtime API

* `LocalLlmBridgeRuntime.load(modelPath)` — loads a caller-provided GGUF model
  and creates a CPU context. The default low-tier configuration is a 2048-token
  context and up to four threads.
* `runtime.generate(prompt)` — performs one independent greedy generation and
  returns complete UTF-8 text. The context is cleared before each request.
* `runtime.close()` — releases the model and context. It is safe to call more
  than once.

Prompts are passed through as complete prompts. Model-specific chat-template
  formatting belongs to the application layer and will be added in a later
  slice. Streaming, cancellation, and isolate orchestration are also outside
  this synchronous runtime slice.

## Binding to native code

Bindings are generated from `src/local_llm_bridge.h` by `package:ffigen`.
Regenerate them with:

```bash
dart run ffigen --config ffigen.yaml
```

## Building and testing

```bash
dart pub get   # resolves deps AND runs the build hook (compiles native code)
dart test      # runs the smoke-API tests against the real native asset
```

## Ownership rules (C ABI)

* Caller-allocated buffers stay caller-owned in both directions; the smoke
  version function performs no heap allocation, so there is nothing to free.
* Runtime handles are opaque pointers owned by the facade and released with
  `local_llm_bridge_runtime_free`.
* Text output stays caller-owned: Dart allocates the output buffer, and the C
  facade writes UTF-8 bytes plus a NUL terminator into it.

## Model smoke check

With the selected Gemma 3 1B IT Q4_K_M model outside the repository:

```bash
dart run tool/runtime_smoke_check.dart \
  /Volumes/Kingsman/Projects/Schools/NoteFlow/gemma-3-1b-it-Q4_K_M.gguf
```
