/// Public platform-neutral entrypoint for local Note persistence.
///
/// The contract is always available. Native targets export the file-backed
/// implementation; Web exports a safe unavailable stub.
library;

export 'database_context_contract.dart';
export 'database_context_stub.dart'
    if (dart.library.io) 'database_context_io.dart';
