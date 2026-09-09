/// Streaming SHA-256 verifier for native local model files.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'model_provisioning_contract.dart';
import 'model_selection.dart';

export 'model_provisioning_contract.dart' show ModelIntegrityException;

/// Verifies model file type, exact byte size, and SHA-256 digest.
final class Sha256ModelIntegrityVerifier implements IModelIntegrityVerifier {
  /// Creates a stateless SHA-256 verifier.
  const Sha256ModelIntegrityVerifier();

  @override
  Future<void> verify({
    required ModelDescriptor model,
    required String filePath,
  }) async {
    _validateDescriptor(model);

    final FileSystemEntityType fileType;
    try {
      fileType = await FileSystemEntity.type(filePath, followLinks: false);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        ModelIntegrityException(
          'could not inspect model file "$filePath": $error',
        ),
        stackTrace,
      );
    }

    if (fileType == FileSystemEntityType.notFound) {
      throw ModelIntegrityException('model file does not exist: $filePath');
    }
    if (fileType != FileSystemEntityType.file) {
      throw ModelIntegrityException(
        'model path is not a regular file: $filePath',
      );
    }

    final File file = File(filePath);
    final int actualSize;
    try {
      actualSize = await file.length();
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        ModelIntegrityException(
          'could not read model file size for "$filePath": $error',
        ),
        stackTrace,
      );
    }
    if (actualSize != model.fileSizeBytes) {
      throw ModelIntegrityException(
        'model file size mismatch for "$filePath": expected '
        '${model.fileSizeBytes} bytes, got $actualSize',
      );
    }

    final _DigestCapture output = _DigestCapture();
    final ByteConversionSink input = sha256.startChunkedConversion(output);
    try {
      // File.openRead delivers bounded chunks. The entire GGUF artifact is
      // never materialized as one byte list in memory.
      await for (final List<int> chunk in file.openRead()) {
        input.add(chunk);
      }
      input.close();
    } on Object catch (error, stackTrace) {
      try {
        input.close();
      } on Object {
        // Preserve the original file/hash error.
      }
      Error.throwWithStackTrace(
        ModelIntegrityException(
          'could not calculate SHA-256 for "$filePath": $error',
        ),
        stackTrace,
      );
    }

    final Digest? digest = output.value;
    if (digest == null) {
      throw ModelIntegrityException(
        'SHA-256 calculation produced no digest for "$filePath"',
      );
    }

    final String actualDigest = digest.toString().toLowerCase();
    final String expectedDigest = model.sha256.trim().toLowerCase();
    if (actualDigest != expectedDigest) {
      throw ModelIntegrityException(
        'SHA-256 mismatch for "$filePath": expected $expectedDigest, '
        'got $actualDigest',
      );
    }
  }

  static void _validateDescriptor(ModelDescriptor model) {
    if (model.fileSizeBytes <= 0) {
      throw const ModelIntegrityException(
        'model descriptor fileSizeBytes must be positive',
      );
    }
    final String digest = model.sha256.trim();
    if (!RegExp(r'^[0-9a-f]{64}$', caseSensitive: false).hasMatch(digest)) {
      throw const ModelIntegrityException(
        'model descriptor sha256 must be exactly 64 hexadecimal characters',
      );
    }
  }
}

final class _DigestCapture implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest event) {
    if (value != null) {
      throw StateError('SHA-256 digest was emitted more than once');
    }
    value = event;
  }

  @override
  void close() {}
}

/// Creates the native streaming verifier used by the composition root.
IModelIntegrityVerifier createModelIntegrityVerifier() {
  return const Sha256ModelIntegrityVerifier();
}
