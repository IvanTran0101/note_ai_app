/// Web implementation of the model integrity verifier API.
library;

import 'model_provisioning_contract.dart';
import 'model_selection.dart';

/// Typed failure type kept for API parity with native targets.
final class ModelIntegrityException implements Exception {
  /// Creates an integrity failure.
  const ModelIntegrityException(this.message);

  /// Explanation suitable for logs or application error mapping.
  final String message;

  @override
  String toString() => 'ModelIntegrityException: $message';
}

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
