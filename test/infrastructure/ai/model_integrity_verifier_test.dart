import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/infrastructure/ai/model_integrity_verifier.dart'
    as facade;
import 'package:note_ai_app/infrastructure/ai/model_integrity_verifier_io.dart';
import 'package:note_ai_app/infrastructure/ai/model_integrity_verifier_stub.dart'
    as stub;
import 'package:note_ai_app/infrastructure/ai/model_selection.dart';

const String _zeroDigest =
    '0000000000000000000000000000000000000000000000000000000000000000';

ModelDescriptor _model({required int fileSizeBytes, required String sha256}) {
  return ModelDescriptor(
    id: 'test-model',
    version: 'test',
    fileName: 'model.gguf',
    downloadUrl: 'https://example.test/model.gguf',
    sha256: sha256,
    fileSizeBytes: fileSizeBytes,
    estimatedPeakMemoryBytes: null,
    requiredFreeStorageBytes: null,
    supportedPlatforms: const <String>['ios'],
    supportedAbis: const <String>['arm64'],
    minOsVersion: '0',
    contextSize: 128,
    maxOutputTokens: 16,
    quantization: 'Q4_K_M',
    selectionPriority: 1,
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('model_verifier_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('accepts exact size and digest', () async {
    final List<int> bytes = <int>[1, 2, 3, 4, 5];
    final File file = File('${tempDir.path}/model.gguf')
      ..writeAsBytesSync(bytes);
    final String digest = sha256.convert(bytes).toString();

    await const Sha256ModelIntegrityVerifier().verify(
      model: _model(fileSizeBytes: bytes.length, sha256: digest),
      filePath: file.path,
    );
  });

  test('compares the digest case-insensitively', () async {
    final List<int> bytes = <int>[10, 20, 30];
    final File file = File('${tempDir.path}/upper.gguf')
      ..writeAsBytesSync(bytes);
    final String digest = sha256.convert(bytes).toString().toUpperCase();

    await const Sha256ModelIntegrityVerifier().verify(
      model: _model(fileSizeBytes: bytes.length, sha256: digest),
      filePath: file.path,
    );
  });

  test('rejects a digest mismatch', () async {
    final List<int> bytes = <int>[1, 2, 3, 4];
    final File file = File('${tempDir.path}/bad-digest.gguf')
      ..writeAsBytesSync(bytes);

    await expectLater(
      const Sha256ModelIntegrityVerifier().verify(
        model: _model(fileSizeBytes: bytes.length, sha256: _zeroDigest),
        filePath: file.path,
      ),
      throwsA(
        isA<ModelIntegrityException>().having(
          (ModelIntegrityException error) => error.message,
          'message',
          contains('SHA-256 mismatch'),
        ),
      ),
    );
  });

  test('rejects an exact-size mismatch before hashing', () async {
    final List<int> bytes = <int>[1, 2, 3, 4];
    final File file = File('${tempDir.path}/bad-size.gguf')
      ..writeAsBytesSync(bytes);

    await expectLater(
      const Sha256ModelIntegrityVerifier().verify(
        model: _model(fileSizeBytes: bytes.length + 1, sha256: _zeroDigest),
        filePath: file.path,
      ),
      throwsA(
        isA<ModelIntegrityException>().having(
          (ModelIntegrityException error) => error.message,
          'message',
          contains('size mismatch'),
        ),
      ),
    );
  });

  test('rejects a missing file', () async {
    await expectLater(
      const Sha256ModelIntegrityVerifier().verify(
        model: _model(fileSizeBytes: 1, sha256: _zeroDigest),
        filePath: '${tempDir.path}/missing.gguf',
      ),
      throwsA(isA<ModelIntegrityException>()),
    );
  });

  test('rejects a directory instead of a regular file', () async {
    final Directory directory = Directory('${tempDir.path}/model.gguf')
      ..createSync();

    await expectLater(
      const Sha256ModelIntegrityVerifier().verify(
        model: _model(fileSizeBytes: 1, sha256: _zeroDigest),
        filePath: directory.path,
      ),
      throwsA(
        isA<ModelIntegrityException>().having(
          (ModelIntegrityException error) => error.message,
          'message',
          contains('regular file'),
        ),
      ),
    );
  });

  test('rejects malformed descriptor metadata', () async {
    final File file = File('${tempDir.path}/malformed.gguf')
      ..writeAsBytesSync(<int>[1]);

    await expectLater(
      const Sha256ModelIntegrityVerifier().verify(
        model: _model(fileSizeBytes: 1, sha256: 'not-a-digest'),
        filePath: file.path,
      ),
      throwsA(isA<ModelIntegrityException>()),
    );
  });

  test('native facade exposes the concrete verifier factory', () {
    expect(
      facade.createModelIntegrityVerifier(),
      isA<Sha256ModelIntegrityVerifier>(),
    );
  });

  test('Web stub rejects local verification', () async {
    final ModelDescriptor model = _model(fileSizeBytes: 1, sha256: _zeroDigest);

    await expectLater(
      const stub.Sha256ModelIntegrityVerifier().verify(
        model: model,
        filePath: '/unavailable/model.gguf',
      ),
      throwsUnsupportedError,
    );
  });
}
