import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_failure.dart';

void main() {
  group('ModelProvisioningFailureCode', () {
    test('exposes the agreed failure codes in a stable order', () {
      expect(
        ModelProvisioningFailureCode.values,
        <ModelProvisioningFailureCode>[
          ModelProvisioningFailureCode.hardwareDetectionFailed,
          ModelProvisioningFailureCode.noCompatibleModel,
          ModelProvisioningFailureCode.storageFailed,
          ModelProvisioningFailureCode.downloadFailed,
          ModelProvisioningFailureCode.integrityMismatch,
          ModelProvisioningFailureCode.runtimeLoadFailed,
          ModelProvisioningFailureCode.unsupportedPlatform,
          ModelProvisioningFailureCode.unexpected,
        ],
      );
    });

    test('assigns every code the agreed retryable flag', () {
      expect(
        ModelProvisioningFailureCode.hardwareDetectionFailed.retryable,
        isTrue,
      );
      expect(ModelProvisioningFailureCode.noCompatibleModel.retryable, isFalse);
      expect(ModelProvisioningFailureCode.storageFailed.retryable, isTrue);
      expect(ModelProvisioningFailureCode.downloadFailed.retryable, isTrue);
      expect(ModelProvisioningFailureCode.integrityMismatch.retryable, isTrue);
      expect(ModelProvisioningFailureCode.runtimeLoadFailed.retryable, isFalse);
      expect(
        ModelProvisioningFailureCode.unsupportedPlatform.retryable,
        isFalse,
      );
      expect(ModelProvisioningFailureCode.unexpected.retryable, isFalse);
    });
  });

  group('ModelProvisioningFailure', () {
    const ModelProvisioningFailure failure = ModelProvisioningFailure(
      code: ModelProvisioningFailureCode.downloadFailed,
      detail: 'The download was interrupted.',
    );

    test('carries its code and optional safe detail', () {
      expect(failure.code, ModelProvisioningFailureCode.downloadFailed);
      expect(failure.detail, 'The download was interrupted.');
    });

    test('defaults detail to null', () {
      const ModelProvisioningFailure bare = ModelProvisioningFailure(
        code: ModelProvisioningFailureCode.unexpected,
      );

      expect(bare.detail, isNull);
    });

    test('derives retryable from the code so they cannot disagree', () {
      const ModelProvisioningFailure retryable = ModelProvisioningFailure(
        code: ModelProvisioningFailureCode.downloadFailed,
      );
      const ModelProvisioningFailure permanent = ModelProvisioningFailure(
        code: ModelProvisioningFailureCode.noCompatibleModel,
      );

      expect(retryable.retryable, isTrue);
      expect(permanent.retryable, isFalse);
    });

    test('treats failures with equal code and detail as equal', () {
      const ModelProvisioningFailure same = ModelProvisioningFailure(
        code: ModelProvisioningFailureCode.downloadFailed,
        detail: 'The download was interrupted.',
      );

      expect(failure, same);
      expect(failure.hashCode, same.hashCode);
    });

    test('distinguishes failures by code and by detail', () {
      const ModelProvisioningFailure otherCode = ModelProvisioningFailure(
        code: ModelProvisioningFailureCode.integrityMismatch,
        detail: 'The download was interrupted.',
      );
      const ModelProvisioningFailure otherDetail = ModelProvisioningFailure(
        code: ModelProvisioningFailureCode.downloadFailed,
        detail: 'Timed out.',
      );
      const ModelProvisioningFailure noDetail = ModelProvisioningFailure(
        code: ModelProvisioningFailureCode.downloadFailed,
      );

      expect(failure == otherCode, isFalse);
      expect(failure == otherDetail, isFalse);
      expect(failure == noDetail, isFalse);
    });

    test('reports code, retryable, and detail in toString', () {
      expect(failure.toString(), contains('code: downloadFailed'));
      expect(failure.toString(), contains('retryable: true'));
      expect(
        failure.toString(),
        contains('detail: The download was interrupted.'),
      );
    });
  });
}
