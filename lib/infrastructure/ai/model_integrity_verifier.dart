/// Public model integrity verifier entrypoint.
///
/// Native targets use a streaming SHA-256 implementation. Web exposes the
/// same verifier API but reports that local filesystem verification is
/// unsupported in the browser runtime.
library;

export 'model_provisioning_contract.dart' show IModelIntegrityVerifier;

export 'model_integrity_verifier_stub.dart'
    if (dart.library.io) 'model_integrity_verifier_io.dart';
