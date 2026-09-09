import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_failure.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_state.dart';

final DateTime _updatedAt = DateTime.utc(2026, 9, 9, 12, 0, 0);

const ModelProvisioningFailure _downloadFailed = ModelProvisioningFailure(
  code: ModelProvisioningFailureCode.downloadFailed,
  detail: 'The download was interrupted.',
);

void main() {
  group('ModelProvisioningPhase', () {
    test('exposes the agreed phases in lifecycle order', () {
      expect(ModelProvisioningPhase.values, <ModelProvisioningPhase>[
        ModelProvisioningPhase.idle,
        ModelProvisioningPhase.detectingDevice,
        ModelProvisioningPhase.selectingModel,
        ModelProvisioningPhase.checkingExistingModel,
        ModelProvisioningPhase.downloading,
        ModelProvisioningPhase.verifying,
        ModelProvisioningPhase.committing,
        ModelProvisioningPhase.artifactReady,
        ModelProvisioningPhase.loadingRuntime,
        ModelProvisioningPhase.ready,
        ModelProvisioningPhase.failed,
      ]);
    });
  });

  group('initial and phase state', () {
    test('defaults to the idle phase with no model and no bytes', () {
      final ModelProvisioningState state = ModelProvisioningState(
        updatedAt: _updatedAt,
      );

      expect(state.phase, ModelProvisioningPhase.idle);
      expect(state.modelId, isNull);
      expect(state.modelName, isNull);
      expect(state.downloadedBytes, 0);
      expect(state.totalBytes, isNull);
      expect(state.failure, isNull);
      expect(state.updatedAt, _updatedAt);
    });

    test('carries model identity and byte progress while downloading', () {
      final ModelProvisioningState state = ModelProvisioningState(
        phase: ModelProvisioningPhase.downloading,
        modelId: 'gemma-3-1b-it',
        modelName: 'gemma-3-1b-it-Q4_K_M.gguf',
        downloadedBytes: 4096,
        totalBytes: 1048576,
        updatedAt: _updatedAt,
      );

      expect(state.phase, ModelProvisioningPhase.downloading);
      expect(state.modelId, 'gemma-3-1b-it');
      expect(state.modelName, 'gemma-3-1b-it-Q4_K_M.gguf');
      expect(state.downloadedBytes, 4096);
      expect(state.totalBytes, 1048576);
      expect(state.failure, isNull);
    });
  });

  group('progress invariants', () {
    test('rejects a negative downloadedBytes', () {
      expect(
        () =>
            ModelProvisioningState(downloadedBytes: -1, updatedAt: _updatedAt),
        throwsArgumentError,
      );
    });

    test('rejects a negative totalBytes', () {
      expect(
        () => ModelProvisioningState(
          downloadedBytes: 10,
          totalBytes: -1,
          updatedAt: _updatedAt,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a zero totalBytes', () {
      expect(
        () => ModelProvisioningState(totalBytes: 0, updatedAt: _updatedAt),
        throwsArgumentError,
      );
    });

    test('rejects downloadedBytes above totalBytes', () {
      expect(
        () => ModelProvisioningState(
          downloadedBytes: 101,
          totalBytes: 100,
          updatedAt: _updatedAt,
        ),
        throwsArgumentError,
      );
    });

    test('accepts downloadedBytes equal to totalBytes', () {
      final ModelProvisioningState state = ModelProvisioningState(
        phase: ModelProvisioningPhase.downloading,
        downloadedBytes: 100,
        totalBytes: 100,
        updatedAt: _updatedAt,
      );

      expect(state.downloadedBytes, 100);
      expect(state.totalBytes, 100);
    });

    test('accepts zero bytes with no total', () {
      final ModelProvisioningState state = ModelProvisioningState(
        phase: ModelProvisioningPhase.checkingExistingModel,
        updatedAt: _updatedAt,
      );

      expect(state.downloadedBytes, 0);
      expect(state.totalBytes, isNull);
    });
  });

  group('nullable totalBytes and indeterminate progress', () {
    test('is indeterminate while downloading with an unknown total', () {
      final ModelProvisioningState state = ModelProvisioningState(
        phase: ModelProvisioningPhase.downloading,
        downloadedBytes: 4096,
        updatedAt: _updatedAt,
      );

      expect(state.totalBytes, isNull);
      expect(state.isIndeterminate, isTrue);
    });

    test('is indeterminate in phases without byte progress', () {
      for (final ModelProvisioningPhase phase in <ModelProvisioningPhase>[
        ModelProvisioningPhase.verifying,
        ModelProvisioningPhase.committing,
        ModelProvisioningPhase.loadingRuntime,
      ]) {
        final ModelProvisioningState state = ModelProvisioningState(
          phase: phase,
          updatedAt: _updatedAt,
        );

        expect(state.totalBytes, isNull, reason: '$phase has no total');
        expect(state.isIndeterminate, isTrue);
      }
    });

    test('is determinate when totalBytes is known', () {
      final ModelProvisioningState state = ModelProvisioningState(
        phase: ModelProvisioningPhase.downloading,
        downloadedBytes: 512,
        totalBytes: 1024,
        updatedAt: _updatedAt,
      );

      expect(state.totalBytes, 1024);
      expect(state.isIndeterminate, isFalse);
    });
  });

  group('failure binding', () {
    test('rejects a failure attached to a non-failed phase', () {
      expect(
        () => ModelProvisioningState(
          phase: ModelProvisioningPhase.downloading,
          failure: _downloadFailed,
          updatedAt: _updatedAt,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a failed phase without a failure', () {
      expect(
        () => ModelProvisioningState(
          phase: ModelProvisioningPhase.failed,
          updatedAt: _updatedAt,
        ),
        throwsArgumentError,
      );
    });

    test('accepts a failed phase carrying its failure', () {
      final ModelProvisioningState state = ModelProvisioningState(
        phase: ModelProvisioningPhase.failed,
        modelId: 'gemma-3-1b-it',
        downloadedBytes: 4096,
        totalBytes: 1048576,
        failure: _downloadFailed,
        updatedAt: _updatedAt,
      );

      expect(state.phase, ModelProvisioningPhase.failed);
      expect(state.failure, _downloadFailed);
    });
  });

  group('value equality', () {
    ModelProvisioningState downloading() {
      return ModelProvisioningState(
        phase: ModelProvisioningPhase.downloading,
        modelId: 'gemma-3-1b-it',
        modelName: 'Gemma 3 1B',
        downloadedBytes: 4096,
        totalBytes: 1048576,
        updatedAt: _updatedAt,
      );
    }

    test('treats snapshots with equal fields as equal', () {
      final ModelProvisioningState a = downloading();
      final ModelProvisioningState b = downloading();

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('distinguishes snapshots by phase', () {
      final ModelProvisioningState a = downloading();
      final ModelProvisioningState b = ModelProvisioningState(
        phase: ModelProvisioningPhase.verifying,
        modelId: 'gemma-3-1b-it',
        modelName: 'Gemma 3 1B',
        downloadedBytes: 4096,
        totalBytes: 1048576,
        updatedAt: _updatedAt,
      );

      expect(a == b, isFalse);
    });

    test('distinguishes snapshots by model identity', () {
      final ModelProvisioningState a = downloading();
      final ModelProvisioningState b = ModelProvisioningState(
        phase: ModelProvisioningPhase.downloading,
        modelId: 'other-model',
        modelName: 'Gemma 3 1B',
        downloadedBytes: 4096,
        totalBytes: 1048576,
        updatedAt: _updatedAt,
      );

      expect(a == b, isFalse);
    });

    test('distinguishes snapshots by byte progress and total', () {
      final ModelProvisioningState a = downloading();
      final ModelProvisioningState b = ModelProvisioningState(
        phase: ModelProvisioningPhase.downloading,
        modelId: 'gemma-3-1b-it',
        modelName: 'Gemma 3 1B',
        downloadedBytes: 4097,
        totalBytes: 1048576,
        updatedAt: _updatedAt,
      );
      final ModelProvisioningState c = ModelProvisioningState(
        phase: ModelProvisioningPhase.downloading,
        modelId: 'gemma-3-1b-it',
        modelName: 'Gemma 3 1B',
        downloadedBytes: 4096,
        updatedAt: _updatedAt,
      );

      expect(a == b, isFalse);
      expect(a == c, isFalse);
    });

    test('distinguishes snapshots by failure', () {
      final ModelProvisioningState a = downloading();
      final ModelProvisioningState b = ModelProvisioningState(
        phase: ModelProvisioningPhase.failed,
        modelId: 'gemma-3-1b-it',
        modelName: 'Gemma 3 1B',
        downloadedBytes: 4096,
        totalBytes: 1048576,
        failure: _downloadFailed,
        updatedAt: _updatedAt,
      );

      expect(a == b, isFalse);
    });

    test('distinguishes snapshots by updatedAt', () {
      final ModelProvisioningState a = downloading();
      final ModelProvisioningState b = ModelProvisioningState(
        phase: ModelProvisioningPhase.downloading,
        modelId: 'gemma-3-1b-it',
        modelName: 'Gemma 3 1B',
        downloadedBytes: 4096,
        totalBytes: 1048576,
        updatedAt: _updatedAt.add(const Duration(seconds: 1)),
      );

      expect(a == b, isFalse);
    });
  });

  group('toString', () {
    test('reports phase, model, byte fields, and failure code', () {
      final ModelProvisioningState downloading = ModelProvisioningState(
        phase: ModelProvisioningPhase.downloading,
        modelId: 'gemma-3-1b-it',
        downloadedBytes: 4096,
        totalBytes: 1048576,
        updatedAt: _updatedAt,
      );
      final ModelProvisioningState failed = ModelProvisioningState(
        phase: ModelProvisioningPhase.failed,
        modelId: 'gemma-3-1b-it',
        downloadedBytes: 4096,
        totalBytes: 1048576,
        failure: _downloadFailed,
        updatedAt: _updatedAt,
      );

      expect(downloading.toString(), contains('phase: downloading'));
      expect(downloading.toString(), contains('modelId: gemma-3-1b-it'));
      expect(downloading.toString(), contains('downloadedBytes: 4096'));
      expect(downloading.toString(), contains('totalBytes: 1048576'));
      expect(downloading.toString(), contains('updatedAt: 2026-09-09'));
      expect(failed.toString(), contains('failure: downloadFailed'));
    });
  });
}
