import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_boundary.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_failure.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_state.dart';
import 'package:note_ai_app/infrastructure/ai/llm_worker_contract.dart';
import 'package:note_ai_app/infrastructure/ai/model_manager.dart';
import 'package:note_ai_app/infrastructure/ai/model_provisioning_contract.dart';
import 'package:note_ai_app/infrastructure/ai/model_selection.dart';
import 'package:note_ai_app/infrastructure/ai/model_storage_contract.dart';
import 'package:note_ai_app/infrastructure/configuration/ai_configuration_store.dart';
import 'package:note_ai_app/infrastructure/device/device_info_plus_hardware_detection_contract.dart';
import 'package:note_ai_app/infrastructure/device/hardware_detection.dart';

const _model = ModelDescriptor(
  id: 'gemma-3-1b-it',
  version: '1.0.0',
  fileName: 'gemma-3-1b-it-Q4_K_M.gguf',
  downloadUrl: 'https://example.invalid/gemma-3-1b-it-Q4_K_M.gguf',
  sha256: '8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135',
  fileSizeBytes: 806058240,
  estimatedPeakMemoryBytes: 2147483648,
  requiredFreeStorageBytes: 1610612736,
  supportedPlatforms: ['ios', 'android'],
  supportedAbis: ['arm64', 'arm64-v8a'],
  minOsVersion: '14.0',
  contextSize: 4096,
  maxOutputTokens: 512,
  quantization: 'Q4_K_M',
  selectionPriority: 1,
);

const _capability = DeviceCapability(
  platform: 'ios',
  osVersion: '18.1',
  isPhysicalDevice: true,
  supportedAbis: ['arm64'],
  totalMemoryBytes: 8589934592,
  freeStorageBytes: 21474836480,
);

void main() {
  group('ModelManager', () {
    test(
      'records preparing and ready for an existing verified model',
      () async {
        final _FakeAiConfigurationStore configurationStore =
            _FakeAiConfigurationStore();
        final ModelManager manager = _manager(
          storage: _FakeStorage(existingPath: '/models/${_model.fileName}'),
          aiConfigurationStore: configurationStore,
        );

        await manager.ensureModelReady();

        expect(
          configurationStore.snapshots.map(
            (AiReadinessSnapshot snapshot) => snapshot.status,
          ),
          <ModelReadinessStatus>[
            ModelReadinessStatus.preparing,
            ModelReadinessStatus.ready,
          ],
        );
        expect(
          configurationStore.snapshots.last.localPath,
          '/models/${_model.fileName}',
        );
      },
    );

    test('records preparing and ready after download and commit', () async {
      final _FakeAiConfigurationStore configurationStore =
          _FakeAiConfigurationStore();
      final ModelManager manager = _manager(
        aiConfigurationStore: configurationStore,
      );

      await manager.ensureModelReady();

      expect(
        configurationStore.snapshots.map(
          (AiReadinessSnapshot snapshot) => snapshot.status,
        ),
        <ModelReadinessStatus>[
          ModelReadinessStatus.preparing,
          ModelReadinessStatus.ready,
        ],
      );
      expect(
        configurationStore.snapshots.last.localPath,
        '/models/${_model.fileName}',
      );
    });

    test(
      'records a bounded failure without replacing the original error',
      () async {
        final StateError expected = StateError('download failed');
        final _FakeAiConfigurationStore configurationStore =
            _FakeAiConfigurationStore();
        final ModelManager manager = _manager(
          aiConfigurationStore: configurationStore,
          downloader: _FakeDownloader(failure: expected),
        );

        await expectLater(manager.ensureModelReady(), throwsA(same(expected)));

        expect(
          configurationStore.snapshots.last.status,
          ModelReadinessStatus.failed,
        );
        expect(
          configurationStore.snapshots.last.lastError,
          contains('download failed'),
        );
        expect(
          configurationStore.snapshots.last.lastError!.length,
          lessThanOrEqualTo(512),
        );
      },
    );

    test(
      'store failures never mask successful or failed provisioning',
      () async {
        final StateError expected = StateError('download failed');
        final _FakeAiConfigurationStore failingStore =
            _FakeAiConfigurationStore(
              saveFailure: StateError('store unavailable'),
            );

        final PreparedModel prepared = await _manager(
          aiConfigurationStore: failingStore,
        ).ensureModelReady();
        expect(prepared.path, '/models/${_model.fileName}');

        await expectLater(
          _manager(
            aiConfigurationStore: failingStore,
            downloader: _FakeDownloader(failure: expected),
          ).ensureModelReady(),
          throwsA(same(expected)),
        );
      },
    );

    test(
      'does not trust stale stored paths and still verifies the current model',
      () async {
        final _FakeAiConfigurationStore configurationStore =
            _FakeAiConfigurationStore(
              initial: AiReadinessSnapshot(
                modelId: _model.id,
                modelVersion: _model.version,
                modelSha256: _model.sha256,
                localPath: '/stale/model.gguf',
                platform: _capability.platform,
                osVersion: _capability.osVersion,
                isPhysicalDevice: _capability.isPhysicalDevice,
                supportedAbis: _capability.supportedAbis,
                status: ModelReadinessStatus.ready,
                updatedAt: DateTime.utc(2026, 9, 4),
              ),
            );
        final _FakeStorage storage = _FakeStorage(
          existingPath: '/models/${_model.fileName}',
        );
        final _FakeVerifier verifier = _FakeVerifier();

        final PreparedModel prepared = await _manager(
          aiConfigurationStore: configurationStore,
          storage: storage,
          verifier: verifier,
        ).ensureModelReady();

        expect(prepared.path, '/models/${_model.fileName}');
        expect(verifier.paths, ['/models/${_model.fileName}']);
      },
    );

    test('no selected model writes no readiness snapshot', () async {
      final _FakeAiConfigurationStore configurationStore =
          _FakeAiConfigurationStore();
      final ModelManager manager = _manager(
        policy: _FakePolicy.noSelection(),
        aiConfigurationStore: configurationStore,
      );

      await expectLater(
        manager.ensureModelReady(),
        throwsA(isA<NoModelSelectedException>()),
      );

      expect(configurationStore.snapshots, isEmpty);
    });

    test('records failed and never discards when an existing model fails '
        'verification', () async {
      final StateError expected = StateError('existing digest mismatch');
      final _FakeAiConfigurationStore configurationStore =
          _FakeAiConfigurationStore();
      final _FakeStorage storage = _FakeStorage(
        existingPath: '/models/${_model.fileName}',
      );
      final ModelManager manager = _manager(
        storage: storage,
        verifier: _FakeVerifier(failure: expected),
        aiConfigurationStore: configurationStore,
      );

      await expectLater(manager.ensureModelReady(), throwsA(same(expected)));

      expect(
        configurationStore.snapshots.last.status,
        ModelReadinessStatus.failed,
      );
      expect(
        configurationStore.snapshots.last.lastError,
        contains('digest mismatch'),
      );
      expect(storage.stagingCreates, isZero);
      expect(storage.discards, isZero);
    });

    test(
      'verifies an existing selected model and skips staging/download',
      () async {
        final _FakeStorage storage = _FakeStorage(
          existingPath: '/models/${_model.fileName}',
        );
        final _FakeVerifier verifier = _FakeVerifier();
        final _FakeDownloader downloader = _FakeDownloader();
        final ModelManager manager = _manager(
          storage: storage,
          verifier: verifier,
          downloader: downloader,
        );

        final PreparedModel prepared = await manager.ensureModelReady();

        expect(prepared.model, _model);
        expect(prepared.path, '/models/${_model.fileName}');
        expect(prepared.detectedCapability, _capability);
        expect(verifier.paths, ['/models/${_model.fileName}']);
        expect(downloader.downloads, isZero);
        expect(storage.stagingCreates, isZero);
        expect(storage.commits, isZero);
      },
    );

    test(
      'stages, downloads, verifies, and commits only the selected model',
      () async {
        final List<String> events = <String>[];
        final _FakeStorage storage = _FakeStorage(events: events);
        final _FakeDownloader downloader = _FakeDownloader(events: events);
        final _FakeVerifier verifier = _FakeVerifier(events: events);
        final ModelManager manager = _manager(
          events: events,
          storage: storage,
          downloader: downloader,
          verifier: verifier,
        );

        final PreparedModel prepared = await manager.ensureModelReady();

        expect(prepared.path, '/models/${_model.fileName}');
        expect(downloader.models, [_model]);
        expect(verifier.paths, ['/staging/${_model.fileName}.part']);
        expect(events, [
          'detect',
          'select',
          'find',
          'stage',
          'download',
          'verify',
          'commit',
        ]);
      },
    );

    test(
      'throws selection exception and does not touch storage or downloader',
      () async {
        final _FakeStorage storage = _FakeStorage();
        final _FakeDownloader downloader = _FakeDownloader();
        final ModelManager manager = _manager(
          storage: storage,
          downloader: downloader,
          policy: _FakePolicy.noSelection(),
        );

        await expectLater(
          manager.ensureModelReady(),
          throwsA(
            isA<NoModelSelectedException>().having(
              (NoModelSelectedException error) =>
                  error.selection.selectionReason,
              'selection reason',
              'no compatible model',
            ),
          ),
        );
        expect(storage.finds, isZero);
        expect(downloader.downloads, isZero);
        expect(storage.stagingCreates, isZero);
      },
    );

    test('discards staging and preserves a download failure', () async {
      final StateError expected = StateError('download failed');
      final _FakeStorage storage = _FakeStorage();
      final ModelManager manager = _manager(
        storage: storage,
        downloader: _FakeDownloader(failure: expected),
      );

      await expectLater(manager.ensureModelReady(), throwsA(same(expected)));

      expect(storage.stagingCreates, 1);
      expect(storage.discards, 1);
      expect(storage.commits, isZero);
    });

    test('discards staging when verification of a download fails', () async {
      final StateError expected = StateError('digest mismatch');
      final _FakeStorage storage = _FakeStorage();
      final ModelManager manager = _manager(
        storage: storage,
        verifier: _FakeVerifier(failure: expected),
      );

      await expectLater(manager.ensureModelReady(), throwsA(same(expected)));

      expect(storage.stagingCreates, 1);
      expect(storage.discards, 1);
      expect(storage.commits, isZero);
    });

    test('discards staging when commit fails', () async {
      final StateError expected = StateError('commit failed');
      final _FakeStorage storage = _FakeStorage(commitFailure: expected);
      final ModelManager manager = _manager(storage: storage);

      await expectLater(manager.ensureModelReady(), throwsA(same(expected)));

      expect(storage.stagingCreates, 1);
      expect(storage.discards, 1);
      expect(storage.commits, 1);
    });

    test(
      'does not discard an existing model when its verification fails',
      () async {
        final StateError expected = StateError('existing digest mismatch');
        final _FakeStorage storage = _FakeStorage(
          existingPath: '/models/${_model.fileName}',
        );
        final ModelManager manager = _manager(
          storage: storage,
          verifier: _FakeVerifier(failure: expected),
        );

        await expectLater(manager.ensureModelReady(), throwsA(same(expected)));

        expect(storage.stagingCreates, isZero);
        expect(storage.discards, isZero);
      },
    );

    test(
      'shares one in-flight operation so concurrent callers download once',
      () async {
        final Completer<void> downloadGate = Completer<void>();
        final Completer<void> downloadStarted = Completer<void>();
        final _FakeAiConfigurationStore configurationStore =
            _FakeAiConfigurationStore();
        final _FakeStorage storage = _FakeStorage();
        final _FakeDownloader downloader = _FakeDownloader(
          gate: downloadGate,
          started: downloadStarted,
        );
        final ModelManager manager = _manager(
          storage: storage,
          downloader: downloader,
          aiConfigurationStore: configurationStore,
        );

        final Future<PreparedModel> first = manager.ensureModelReady();
        final Future<PreparedModel> second = manager.ensureModelReady();

        expect(identical(first, second), isTrue);
        await downloadStarted.future;
        expect(downloader.downloads, 1);
        downloadGate.complete();

        final List<PreparedModel> prepared = await Future.wait(
          <Future<PreparedModel>>[first, second],
        );
        expect(prepared[0], prepared[1]);
        expect(storage.stagingCreates, 1);
        expect(storage.commits, 1);
        expect(
          configurationStore.snapshots.map(
            (AiReadinessSnapshot snapshot) => snapshot.status,
          ),
          <ModelReadinessStatus>[
            ModelReadinessStatus.preparing,
            ModelReadinessStatus.ready,
          ],
        );
      },
    );

    group('M4.5.a provisioning snapshots', () {
      test(
        'publishes existing-model phases with identity and never ready',
        () async {
          final _RecordingReporter reporter = _RecordingReporter();
          final ModelManager manager = _manager(
            storage: _FakeStorage(existingPath: '/models/${_model.fileName}'),
            reporter: reporter,
          );

          await manager.ensureModelReady();

          final List<ModelProvisioningState> snapshots = reporter.snapshots;
          expect(
            snapshots.map((ModelProvisioningState state) => state.phase),
            <ModelProvisioningPhase>[
              ModelProvisioningPhase.detectingDevice,
              ModelProvisioningPhase.selectingModel,
              ModelProvisioningPhase.checkingExistingModel,
              ModelProvisioningPhase.verifying,
              ModelProvisioningPhase.artifactReady,
            ],
          );
          // The manager's own terminal success phase is artifactReady; the
          // runtime phases belong to the composition root.
          expect(
            snapshots.map((s) => s.phase),
            isNot(contains(ModelProvisioningPhase.loadingRuntime)),
          );
          expect(
            snapshots.map((s) => s.phase),
            isNot(contains(ModelProvisioningPhase.ready)),
          );
          expect(
            snapshots.map((s) => s.phase),
            isNot(contains(ModelProvisioningPhase.failed)),
          );

          final List<ModelProvisioningState> withModel = snapshots
              .skip(2)
              .toList();
          for (final ModelProvisioningState state in withModel) {
            expect(state.modelId, _model.id);
            expect(state.modelName, _model.fileName);
          }
          for (final ModelProvisioningState state in snapshots) {
            expect(state.updatedAt.isUtc, isTrue);
            expect(state.failure, isNull);
            expect(state.downloadedBytes, 0);
            expect(state.totalBytes, isNull);
            expect(state.isIndeterminate, isTrue);
          }
          expect(identical(reporter.current, snapshots.last), isTrue);
        },
      );

      test(
        'publishes downloading progress bounded by the descriptor size',
        () async {
          final _RecordingReporter reporter = _RecordingReporter();
          final _FakeStorage storage = _FakeStorage();
          final ModelManager manager = _manager(
            storage: storage,
            downloader: _FakeDownloader(progressSteps: <int>[2048, 4096]),
            reporter: reporter,
          );

          await manager.ensureModelReady();

          final List<ModelProvisioningState> snapshots = reporter.snapshots;
          expect(
            snapshots.map((ModelProvisioningState state) => state.phase),
            <ModelProvisioningPhase>[
              ModelProvisioningPhase.detectingDevice,
              ModelProvisioningPhase.selectingModel,
              ModelProvisioningPhase.checkingExistingModel,
              ModelProvisioningPhase.downloading,
              ModelProvisioningPhase.downloading,
              ModelProvisioningPhase.downloading,
              ModelProvisioningPhase.verifying,
              ModelProvisioningPhase.committing,
              ModelProvisioningPhase.artifactReady,
            ],
          );
          final List<ModelProvisioningState> downloading = snapshots
              .where((s) => s.phase == ModelProvisioningPhase.downloading)
              .toList();
          // The descriptor declares the artifact size, so progress is determinate.
          for (final ModelProvisioningState state in downloading) {
            expect(state.modelId, _model.id);
            expect(state.modelName, _model.fileName);
            expect(state.totalBytes, _model.fileSizeBytes);
            expect(state.isIndeterminate, isFalse);
            expect(state.failure, isNull);
          }
          expect(
            downloading.map((s) => s.downloadedBytes),
            <int>[0, 2048, 4096],
            reason:
                'progress is cumulative from the phase start to the last byte',
          );
          for (final ModelProvisioningState state in downloading) {
            expect(state.downloadedBytes, lessThanOrEqualTo(state.totalBytes!));
          }
        },
      );

      test(
        'never publishes ready or loadingRuntime after a download',
        () async {
          final _RecordingReporter reporter = _RecordingReporter();
          final ModelManager manager = _manager(reporter: reporter);

          await manager.ensureModelReady();

          final List<ModelProvisioningState> snapshots = reporter.snapshots;
          expect(snapshots.last.phase, ModelProvisioningPhase.artifactReady);
          expect(
            snapshots.map((s) => s.phase),
            isNot(contains(ModelProvisioningPhase.ready)),
          );
          expect(
            snapshots.map((s) => s.phase),
            isNot(contains(ModelProvisioningPhase.loadingRuntime)),
          );
          expect(
            snapshots.map((s) => s.phase),
            isNot(contains(ModelProvisioningPhase.failed)),
          );
        },
      );

      test('publishes hardware detection failure as failed', () async {
        final HardwareDetectionException expected = HardwareDetectionException(
          'device info unavailable',
        );
        final _RecordingReporter reporter = _RecordingReporter();
        final _FakeStorage storage = _FakeStorage();
        final ModelManager manager = _manager(
          storage: storage,
          hardware: _FakeHardware(failure: expected),
          reporter: reporter,
        );

        await expectLater(manager.ensureModelReady(), throwsA(same(expected)));

        final List<ModelProvisioningState> snapshots = reporter.snapshots;
        expect(snapshots.last.phase, ModelProvisioningPhase.failed);
        expect(
          snapshots.last.failure!.code,
          ModelProvisioningFailureCode.hardwareDetectionFailed,
        );
        expect(storage.finds, isZero);
      });

      test(
        'publishes no-compatible-model as failed without readiness',
        () async {
          final _RecordingReporter reporter = _RecordingReporter();
          final _FakeAiConfigurationStore configurationStore =
              _FakeAiConfigurationStore();
          final ModelManager manager = _manager(
            policy: _FakePolicy.noSelection(),
            aiConfigurationStore: configurationStore,
            reporter: reporter,
          );

          await expectLater(
            manager.ensureModelReady(),
            throwsA(isA<NoModelSelectedException>()),
          );

          final List<ModelProvisioningState> snapshots = reporter.snapshots;
          expect(
            snapshots.map((ModelProvisioningState state) => state.phase),
            <ModelProvisioningPhase>[
              ModelProvisioningPhase.detectingDevice,
              ModelProvisioningPhase.selectingModel,
              ModelProvisioningPhase.failed,
            ],
          );
          expect(
            snapshots.last.failure!.code,
            ModelProvisioningFailureCode.noCompatibleModel,
          );
          expect(configurationStore.snapshots, isEmpty);
        },
      );

      test(
        'maps a download exception to downloadFailed with safe detail',
        () async {
          final ModelDownloadException expected = ModelDownloadException(
            'download failed for https://example.invalid/model.gguf',
          );
          final _RecordingReporter reporter = _RecordingReporter();
          final ModelManager manager = _manager(
            downloader: _FakeDownloader(failure: expected),
            reporter: reporter,
          );

          await expectLater(
            manager.ensureModelReady(),
            throwsA(same(expected)),
          );

          final ModelProvisioningState failed = reporter.snapshots.last;
          expect(failed.phase, ModelProvisioningPhase.failed);
          final ModelProvisioningFailure failure = failed.failure!;
          expect(failure.code, ModelProvisioningFailureCode.downloadFailed);
          expect(failure.retryable, isTrue);
          expect(failure.detail, isNotNull);
          expect(failure.detail, isNot(contains('https://')));
          expect(failure.detail, isNot(contains('example.invalid')));
          expect(failure.detail!.length, lessThanOrEqualTo(120));
        },
      );

      test(
        'maps integrity, storage, and unexpected failures to their codes',
        () async {
          Future<ModelProvisioningFailure> runFailure({
            required Object error,
            IModelDownloader? downloader,
            IModelStorage? storage,
            IModelIntegrityVerifier? verifier,
          }) async {
            final _RecordingReporter reporter = _RecordingReporter();
            final ModelManager manager = _manager(
              downloader: downloader ?? _FakeDownloader(),
              storage: storage ?? _FakeStorage(),
              verifier: verifier ?? _FakeVerifier(),
              reporter: reporter,
            );
            await expectLater(manager.ensureModelReady(), throwsA(same(error)));
            return reporter.snapshots.last.failure!;
          }

          final ModelProvisioningFailure integrity = await runFailure(
            error: const ModelIntegrityException(
              'sha mismatch for /models/model.gguf',
            ),
            verifier: _FakeVerifier(
              failure: const ModelIntegrityException(
                'sha mismatch for /models/model.gguf',
              ),
            ),
          );
          expect(
            integrity.code,
            ModelProvisioningFailureCode.integrityMismatch,
          );
          expect(integrity.detail, isNot(contains('/models/')));

          final ModelProvisioningFailure storage = await runFailure(
            error: const ModelStorageException(
              'failed to resolve the app support directory',
            ),
            storage: _FakeStorage(
              findFailure: const ModelStorageException(
                'failed to resolve the app support directory',
              ),
            ),
          );
          expect(storage.code, ModelProvisioningFailureCode.storageFailed);

          final ModelProvisioningFailure missing = await runFailure(
            error: const ModelNotFoundException('/models/model.gguf'),
            storage: _FakeStorage(
              findFailure: const ModelNotFoundException('/models/model.gguf'),
            ),
          );
          expect(
            missing.code,
            ModelProvisioningFailureCode.storageFailed,
            reason: 'ModelNotFoundException extends ModelStorageException',
          );

          final StateError unexpectedError = StateError('mystery failure');
          final ModelProvisioningFailure unexpected = await runFailure(
            error: unexpectedError,
            downloader: _FakeDownloader(failure: unexpectedError),
          );
          expect(unexpected.code, ModelProvisioningFailureCode.unexpected);
          expect(unexpected.retryable, isFalse);
        },
      );

      test(
        'a runtime-load exception never becomes artifactReady or ready',
        () async {
          final LlmWorkerException expected = LlmWorkerException(
            'worker isolate failed during startup',
          );
          final _RecordingReporter reporter = _RecordingReporter();
          final ModelManager manager = _manager(
            verifier: _FakeVerifier(failure: expected),
            reporter: reporter,
          );

          await expectLater(
            manager.ensureModelReady(),
            throwsA(same(expected)),
          );

          final List<ModelProvisioningState> snapshots = reporter.snapshots;
          expect(snapshots.last.phase, ModelProvisioningPhase.failed);
          expect(
            snapshots.last.failure!.code,
            ModelProvisioningFailureCode.runtimeLoadFailed,
          );
          expect(snapshots.last.failure!.retryable, isFalse);
          expect(
            snapshots.map((s) => s.phase),
            isNot(contains(ModelProvisioningPhase.artifactReady)),
          );
          expect(
            snapshots.map((s) => s.phase),
            isNot(contains(ModelProvisioningPhase.ready)),
          );
          expect(
            snapshots.map((s) => s.phase),
            isNot(contains(ModelProvisioningPhase.loadingRuntime)),
          );
        },
      );

      test(
        'concurrent callers publish exactly one provisioning sequence',
        () async {
          final Completer<void> downloadGate = Completer<void>();
          final Completer<void> downloadStarted = Completer<void>();
          final _RecordingReporter reporter = _RecordingReporter();
          final ModelManager manager = _manager(
            downloader: _FakeDownloader(
              gate: downloadGate,
              started: downloadStarted,
            ),
            reporter: reporter,
          );

          final Future<PreparedModel> first = manager.ensureModelReady();
          final Future<PreparedModel> second = manager.ensureModelReady();
          expect(identical(first, second), isTrue);
          await downloadStarted.future;
          downloadGate.complete();
          await Future.wait(<Future<PreparedModel>>[first, second]);

          final List<ModelProvisioningState> snapshots = reporter.snapshots;
          expect(
            snapshots.where(
              (s) => s.phase == ModelProvisioningPhase.detectingDevice,
            ),
            hasLength(1),
            reason: 'one shared operation publishes one lifecycle',
          );
          expect(snapshots.last.phase, ModelProvisioningPhase.artifactReady);
          expect(
            snapshots.map((s) => s.phase),
            isNot(contains(ModelProvisioningPhase.ready)),
          );
        },
      );

      test('a throwing reporter never masks successful provisioning', () async {
        final ModelManager manager = _manager(reporter: _ThrowingReporter());

        final PreparedModel prepared = await manager.ensureModelReady();

        expect(prepared.path, '/models/${_model.fileName}');
      });
    });
  });

  group('mapModelProvisioningFailure', () {
    ModelProvisioningFailure expectCode(
      Object error,
      ModelProvisioningFailureCode code,
    ) {
      final ModelProvisioningFailure failure = mapModelProvisioningFailure(
        error,
      );
      expect(failure.code, code);
      expect(failure.detail, isNotNull);
      expect(failure.detail!.length, lessThanOrEqualTo(120));
      expect(failure.detail, isNot(contains('https://')));
      expect(failure.detail, isNot(contains('/models/')));
      expect(failure.retryable, code.retryable);
      return failure;
    }

    test('maps every expected failure class to its stable code', () {
      const ModelSelectionResult noSelection = ModelSelectionResult(
        selectedModel: null,
        rejectionReasons: <String, String>{},
        selectionReason: 'none',
      );
      expectCode(
        const NoModelSelectedException(
          capability: _capability,
          selection: noSelection,
        ),
        ModelProvisioningFailureCode.noCompatibleModel,
      );
      expectCode(
        const HardwareDetectionException('detection failed'),
        ModelProvisioningFailureCode.hardwareDetectionFailed,
      );
      expectCode(
        const ModelDownloadException('download failed'),
        ModelProvisioningFailureCode.downloadFailed,
      );
      expectCode(
        const ModelIntegrityException('digest mismatch'),
        ModelProvisioningFailureCode.integrityMismatch,
      );
      expectCode(
        const ModelStorageException('storage failed'),
        ModelProvisioningFailureCode.storageFailed,
      );
      expectCode(
        const ModelNotFoundException('model missing'),
        ModelProvisioningFailureCode.storageFailed,
        // ModelNotFoundException extends ModelStorageException.
      );
      expectCode(
        const LlmWorkerException('startup failed'),
        ModelProvisioningFailureCode.runtimeLoadFailed,
      );
      expectCode(
        UnsupportedError('local models unsupported on this platform'),
        ModelProvisioningFailureCode.unsupportedPlatform,
      );
      expectCode(
        StateError('unmapped'),
        ModelProvisioningFailureCode.unexpected,
      );
    });

    test('never leaks exception text into the failure detail', () {
      final ModelProvisioningFailure failure = mapModelProvisioningFailure(
        ModelDownloadException(
          'GET https://huggingface.co/evil/../../secret.gguf failed with '
          'raw path /Users/me/.cache/models/model.gguf',
        ),
      );
      expect(failure.code, ModelProvisioningFailureCode.downloadFailed);
      expect(failure.detail, isNot(contains('huggingface')));
      expect(failure.detail, isNot(contains('https://')));
      expect(failure.detail, isNot(contains('.gguf')));
      expect(failure.detail, isNot(contains('/Users/')));
    });
  });
}

ModelManager _manager({
  List<String>? events,
  IModelStorage? storage,
  IModelDownloader? downloader,
  IModelIntegrityVerifier? verifier,
  IModelSelectionPolicy? policy,
  IHardwareDetectionService? hardware,
  AiConfigurationStore? aiConfigurationStore,
  IModelProvisioningReporter? reporter,
}) {
  return ModelManager(
    hardwareDetectionService: hardware ?? _FakeHardware(events: events),
    modelSelectionPolicy: policy ?? _FakePolicy(events: events),
    modelCatalog: const _FakeCatalog(<ModelDescriptor>[_model]),
    modelStorage: storage ?? _FakeStorage(events: events),
    modelDownloader: downloader ?? _FakeDownloader(events: events),
    integrityVerifier: verifier ?? _FakeVerifier(events: events),
    aiConfigurationStore: aiConfigurationStore,
    modelProvisioningReporter: reporter,
  );
}

final class _FakeHardware implements IHardwareDetectionService {
  _FakeHardware({this.events, this.failure});

  final List<String>? events;
  final Object? failure;

  @override
  Future<DeviceCapability> getDeviceCapability() async {
    events?.add('detect');
    final Object? error = failure;
    if (error != null) {
      throw error;
    }
    return _capability;
  }
}

final class _FakePolicy implements IModelSelectionPolicy {
  const _FakePolicy({this.events}) : _noSelectionResult = null;

  _FakePolicy.noSelection()
    : events = null,
      _noSelectionResult = const ModelSelectionResult(
        selectedModel: null,
        rejectionReasons: <String, String>{
          'gemma-3-1b-it': 'memory gate: insufficient memory',
        },
        selectionReason: 'no compatible model',
      );

  final List<String>? events;
  final ModelSelectionResult? _noSelectionResult;

  @override
  ModelSelectionResult select({
    required DeviceCapability capability,
    required List<ModelDescriptor> candidates,
  }) {
    events?.add('select');
    return _noSelectionResult ??
        ModelSelectionResult(
          selectedModel: candidates.single,
          rejectionReasons: const <String, String>{},
          selectionReason: 'selected test model',
        );
  }
}

final class _FakeCatalog implements IModelCatalog {
  const _FakeCatalog(this.models);

  @override
  final List<ModelDescriptor> models;
}

final class _FakeStorage implements IModelStorage {
  _FakeStorage({
    this.events,
    this.existingPath,
    this.commitFailure,
    this.findFailure,
  });

  final List<String>? events;
  final String? existingPath;
  final Object? commitFailure;
  final Object? findFailure;
  int finds = 0;
  int stagingCreates = 0;
  int commits = 0;
  int discards = 0;

  @override
  Future<String?> findModel(ModelDescriptor model) async {
    events?.add('find');
    finds++;
    final Object? error = findFailure;
    if (error != null) {
      throw error;
    }
    return existingPath;
  }

  @override
  Future<ModelStagingFile> createStagingFile(ModelDescriptor model) async {
    events?.add('stage');
    stagingCreates++;
    return ModelStagingFile(
      model: model,
      path: '/staging/${model.fileName}.part',
    );
  }

  @override
  Future<String> commitStagingFile(ModelStagingFile stagingFile) async {
    events?.add('commit');
    commits++;
    final Object? error = commitFailure;
    if (error != null) {
      throw error;
    }
    return '/models/${stagingFile.model.fileName}';
  }

  @override
  Future<void> discardStagingFile(ModelStagingFile stagingFile) async {
    discards++;
  }

  @override
  Future<String> resolveModelPath() async =>
      throw UnsupportedError('unused by ModelManager');
}

final class _FakeDownloader implements IModelDownloader {
  _FakeDownloader({
    this.events,
    this.failure,
    this.gate,
    this.started,
    this.progressSteps,
  });

  final List<String>? events;
  final Object? failure;
  final Completer<void>? gate;
  final Completer<void>? started;
  final List<int>? progressSteps;
  int downloads = 0;
  final List<ModelDescriptor> models = <ModelDescriptor>[];

  @override
  Future<void> download({
    required ModelDescriptor model,
    required ModelStagingFile target,
    ModelDownloadProgress? onProgress,
  }) async {
    events?.add('download');
    downloads++;
    models.add(model);
    started?.complete();
    final Object? error = failure;
    if (error != null) {
      throw error;
    }
    final List<int>? steps = progressSteps;
    if (steps != null && onProgress != null) {
      for (final int step in steps) {
        onProgress(step);
      }
    }
    final Completer<void>? waitFor = gate;
    if (waitFor != null) {
      await waitFor.future;
    }
  }
}

final class _FakeVerifier implements IModelIntegrityVerifier {
  _FakeVerifier({this.events, this.failure});

  final List<String>? events;
  final Object? failure;
  final List<String> paths = <String>[];

  @override
  Future<void> verify({
    required ModelDescriptor model,
    required String filePath,
  }) async {
    events?.add('verify');
    paths.add(filePath);
    final Object? error = failure;
    if (error != null) {
      throw error;
    }
  }
}

final class _FakeAiConfigurationStore implements AiConfigurationStore {
  _FakeAiConfigurationStore({this.initial, this.saveFailure});

  final AiReadinessSnapshot? initial;
  final Object? saveFailure;
  final List<AiReadinessSnapshot> snapshots = <AiReadinessSnapshot>[];

  @override
  Future<AiReadinessSnapshot?> read() async => initial;

  @override
  Future<void> save(AiReadinessSnapshot snapshot) async {
    final Object? error = saveFailure;
    if (error != null) {
      throw error;
    }
    snapshots.add(snapshot);
  }

  @override
  Future<void> clear() async {}
}

/// Records every snapshot handed to [IModelProvisioningReporter.publish].
final class _RecordingReporter implements IModelProvisioningReporter {
  final List<ModelProvisioningState> snapshots = <ModelProvisioningState>[];
  ModelProvisioningState? current;

  @override
  void publish(ModelProvisioningState state) {
    current = state;
    snapshots.add(state);
  }
}

/// A reporter whose failure must not alter provisioning semantics.
final class _ThrowingReporter implements IModelProvisioningReporter {
  @override
  void publish(ModelProvisioningState state) {
    throw StateError('reporter unavailable');
  }
}
