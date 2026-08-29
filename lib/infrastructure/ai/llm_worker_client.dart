/// Public entrypoint for the LLM worker client.
///
/// On platforms with `dart:io` this resolves to the isolate-backed
/// implementation (`llm_worker_client_io.dart`). On the Web — where isolates
/// cannot host FFI and no local runtime exists — it resolves to
/// `llm_worker_client_stub.dart`, whose [startLlmWorkerClient] returns an
/// [UnavailableLlmWorkerClient] that throws [UnsupportedError] on every
/// request. There is NO local inference on the Web; Web builds must use a
/// separate remote inference path (future work).
library;

export 'llm_worker_contract.dart';

export 'llm_worker_client_stub.dart'
    if (dart.library.io) 'llm_worker_client_io.dart';
