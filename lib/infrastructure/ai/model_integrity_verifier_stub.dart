/// Web implementation of the model integrity verifier API.
library;

import 'model_provisioning_contract.dart';
import 'model_selection.dart';

export 'model_provisioning_contract.dart' show ModelIntegrityException;

/// Web stub; local filesystem model verification is unavailable in a browser.
final class Sha256ModelIntegrityVerifier implements IModelIntegrityVerifier {
  /// Creates the Web stub.
  const Sha256ModelIntegrityVerifier();

  @override
  Future<void> verify({
    required ModelDescriptor model,
    required String filePath,
  }) async {
    throw UnsupportedError(
      'Local model integrity verification is not available on Web; '
      'use a remote inference path.',
    );
  }
}

/// Creates the Web verifier stub.
IModelIntegrityVerifier createModelIntegrityVerifier() {
  return const Sha256ModelIntegrityVerifier();
}
