/// Public entrypoint for the `local_llm_bridge` package (smoke slice).
///
/// On platforms with `dart:ffi` (Android, iOS, macOS, Windows, Linux), this
/// library resolves to [local_llm_bridge_io] and calls the native C ABI
/// facade through FFI. On the Web — where `dart:ffi` and native assets are
/// unavailable — it resolves to [local_llm_bridge_stub], which exposes the
/// same API but throws [UnsupportedError]. There is NO local inference on the
/// Web; Web builds must use a separate remote inference path (future work).
///
/// The native implementation exposes the synchronous llama.cpp runtime and
/// the original smoke functions. Runtime calls are intentionally unavailable
/// on Web; Web builds must use a separate remote inference path.
library;

export 'local_llm_bridge_stub.dart'
    if (dart.library.ffi) 'local_llm_bridge_io.dart';
