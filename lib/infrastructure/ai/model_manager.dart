/// Single-model provisioning orchestration with advisory readiness state
/// (M3.3a/M4.4) and optional Application provisioning snapshots (M4.5.a).
///
/// This class coordinates the infrastructure contracts only. It does not
/// contain a model catalog, download implementation, digest implementation,
/// platform detection implementation, or local LLM runtime code.
///
/// When an [IModelProvisioningReporter] is injected, the manager publishes the
/// Application state snapshots it owns: `detectingDevice`, `selectingModel`,
/// `checkingExistingModel`, `downloading` (with cumulative progress),
/// `verifying`, `committing`, `artifactReady`, or `failed`. It never publishes
/// `loadingRuntime` or `ready` — those belong to the composition root around
/// the native runtime start.
library;

import 'dart:async';

import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_boundary.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_failure.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_state.dart';

import '../configuration/ai_configuration_store.dart';
import '../device/device_info_plus_hardware_detection_contract.dart';
import '../device/hardware_detection.dart';
import 'llm_worker_contract.dart';
import 'model_provisioning_contract.dart';
import 'model_selection.dart';
import '../../evidence/trace.dart';
import 'model_storage_contract.dart';

/// Safe, short, user-presentable prose for each provisioning failure class.
///
/// Kept deliberately free of any exception text so a stack trace, URL, or raw
/// file path can never reach the Application state through [detail].
const Map<ModelProvisioningFailureCode, String> _failureDetailByCode =
    <ModelProvisioningFailureCode, String>{
      ModelProvisioningFailureCode.hardwareDetectionFailed:
          'Device capability detection failed.',
      ModelProvisioningFailureCode.noCompatibleModel:
          'No compatible model is available for this device.',
      ModelProvisioningFailureCode.storageFailed:
          'The model artifact could not be stored on this device.',
      ModelProvisioningFailureCode.downloadFailed: 'The model download failed.',
      ModelProvisioningFailureCode.integrityMismatch:
          'The downloaded model failed its integrity check.',
      ModelProvisioningFailureCode.runtimeLoadFailed:
          'The local model runtime could not start.',
      ModelProvisioningFailureCode.unsupportedPlatform:
          'Local models are not supported on this platform.',
      ModelProvisioningFailureCode.unexpected:
          'Model setup failed unexpectedly.',
    };

/// Maps one Infrastructure exception onto the Application failure vocabulary.
///
/// This is the single failure-mapping point of the M4.5.a reporting adapter:
/// [ModelManager] and the composition root both use it, so every expected
/// failure class maps to the same stable code everywhere. [detail] is always
/// safe short prose from [_failureDetailByCode]; the original error text never
/// crosses into the Application state.
ModelProvisioningFailure mapModelProvisioningFailure(Object error) {
  final ModelProvisioningFailureCode code = switch (error) {
    NoModelSelectedException() =>
      ModelProvisioningFailureCode.noCompatibleModel,
    HardwareDetectionException() =>
      ModelProvisioningFailureCode.hardwareDetectionFailed,
    ModelDownloadException() => ModelProvisioningFailureCode.downloadFailed,
    ModelIntegrityException() => ModelProvisioningFailureCode.integrityMismatch,
    ModelStorageException() => ModelProvisioningFailureCode.storageFailed,
    LlmWorkerException() => ModelProvisioningFailureCode.runtimeLoadFailed,
    UnsupportedError() => ModelProvisioningFailureCode.unsupportedPlatform,
    _ => ModelProvisioningFailureCode.unexpected,
  };
  return ModelProvisioningFailure(
    code: code,
    detail: _failureDetailByCode[code],
  );
}

/// Coordinates the lifecycle of one model selected for the current device.
///
/// The lifecycle is deliberately linear:
///
/// ```text
/// detect -> select -> locate -> stage -> download -> verify -> commit
/// ```
///
/// A model already present locally skips staging and downloading, but is still
/// integrity-verified before it is returned. A failed staging operation is
/// discarded best-effort; an existing model is never discarded by this class.
final class ModelManager implements IModelManager {
  /// Creates a model manager from its infrastructure collaborators.
  ///
  /// [modelProvisioningReporter] is optional: when present the manager
  /// publishes the Application provisioning snapshots described in the library
  /// doc; reporting is advisory and never changes provisioning semantics.
  ModelManager({
    required IHardwareDetectionService hardwareDetectionService,
    required IModelSelectionPolicy modelSelectionPolicy,
    required IModelCatalog modelCatalog,
    required IModelStorage modelStorage,
    required IModelDownloader modelDownloader,
    required IModelIntegrityVerifier integrityVerifier,
    AiConfigurationStore? aiConfigurationStore,
    IModelProvisioningReporter? modelProvisioningReporter,
  }) : this._(
         hardwareDetectionService,
         modelSelectionPolicy,
         modelCatalog,
         modelStorage,
         modelDownloader,
         integrityVerifier,
         aiConfigurationStore,
         modelProvisioningReporter,
       );

  ModelManager._(
    this._hardwareDetectionService,
    this._modelSelectionPolicy,
    this._modelCatalog,
    this._modelStorage,
    this._modelDownloader,
    this._integrityVerifier,
    this._aiConfigurationStore,
    this._modelProvisioningReporter,
  );

  final IHardwareDetectionService _hardwareDetectionService;
  final IModelSelectionPolicy _modelSelectionPolicy;
  final IModelCatalog _modelCatalog;
  final IModelStorage _modelStorage;
  final IModelDownloader _modelDownloader;
  final IModelIntegrityVerifier _integrityVerifier;
  final AiConfigurationStore? _aiConfigurationStore;
  final IModelProvisioningReporter? _modelProvisioningReporter;

  /// The current provisioning operation, if one is already running.
  Future<PreparedModel>? _inFlight;

  /// Cancellation token owned by the current single-flight operation.
  ModelProvisioningCancellationToken? _activeCancellation;

  /// Returns the current operation when present; otherwise starts exactly one
  /// operation and shares it with concurrent callers.
  @override
  Future<PreparedModel> ensureModelReady() {
    final Future<PreparedModel>? current = _inFlight;
    if (current != null) {
      return current;
    }

    final ModelProvisioningCancellationToken cancellation =
        ModelProvisioningCancellationToken();
    final Future<PreparedModel> started = _prepareModel(cancellation);
    _inFlight = started;
    _activeCancellation = cancellation;

    // Clear the guard after either success or failure. The derived future
    // intentionally handles the error so it cannot become an unhandled error;
    // the original future returned to the caller retains the original error.
    unawaited(
      started.then<void>(
        (_) => _clearInFlight(started, cancellation),
        onError: (Object error, StackTrace stackTrace) {
          _clearInFlight(started, cancellation);
        },
      ),
    );

    return started;
  }

  @override
  bool cancelProvisioning() {
    final ModelProvisioningCancellationToken? cancellation =
        _activeCancellation;
    if (cancellation == null || _inFlight == null) {
      return false;
    }
    cancellation.cancel();
    return true;
  }

  Future<void> _clearInFlight(
    Future<PreparedModel> operation,
    ModelProvisioningCancellationToken cancellation,
  ) async {
    if (identical(_inFlight, operation)) {
      _inFlight = null;
      if (identical(_activeCancellation, cancellation)) {
        _activeCancellation = null;
      }
    }
  }

  Future<PreparedModel> _prepareModel(
    ModelProvisioningCancellationToken cancellation,
  ) async {
    ModelDescriptor? selectedModel;
    DeviceCapability? capability;
    ModelStagingFile? stagingFile;
    String? existingPath;

    try {
      await _cleanupStagingBestEffort();
      cancellation.throwIfCancelled();

      _publishPhase(ModelProvisioningPhase.detectingDevice);
      capability = await _hardwareDetectionService.getDeviceCapability();
      cancellation.throwIfCancelled();

      _publishPhase(ModelProvisioningPhase.selectingModel);
      final ModelSelectionResult selection = _modelSelectionPolicy.select(
        capability: capability,
        candidates: _modelCatalog.models,
      );
      evidenceTrace('hardware_selection', <String, Object?>{
        'platform': capability.platform,
        'os_version': capability.osVersion,
        'physical': capability.isPhysicalDevice,
        'abis': capability.supportedAbis,
        'total_memory_bytes': capability.totalMemoryBytes,
        'free_storage_bytes': capability.freeStorageBytes,
        'selected_model': selection.selectedModel?.id,
        'reason': selection.selectionReason,
        'rejections': selection.rejectionReasons,
      });
      cancellation.throwIfCancelled();
      selectedModel = selection.selectedModel;
      if (selectedModel == null) {
        throw NoModelSelectedException(
          capability: capability,
          selection: selection,
        );
      }

      _publishPhase(
        ModelProvisioningPhase.checkingExistingModel,
        model: selectedModel,
      );
      await _saveReadinessBestEffort(
        _snapshot(
          model: selectedModel,
          capability: capability,
          status: ModelReadinessStatus.preparing,
        ),
      );
      cancellation.throwIfCancelled();

      existingPath = await _modelStorage.findModel(selectedModel);
      cancellation.throwIfCancelled();
      if (existingPath != null) {
        _publishPhase(ModelProvisioningPhase.verifying, model: selectedModel);
        await _integrityVerifier.verify(
          model: selectedModel,
          filePath: existingPath,
        );
        cancellation.throwIfCancelled();
        await _saveReadinessBestEffort(
          _snapshot(
            model: selectedModel,
            capability: capability,
            status: ModelReadinessStatus.ready,
            localPath: existingPath,
          ),
        );
        _publishPhase(
          ModelProvisioningPhase.artifactReady,
          model: selectedModel,
        );
        return PreparedModel(
          selectedModel: selectedModel,
          localPath: existingPath,
          capability: capability,
        );
      }

      stagingFile = await _modelStorage.createStagingFile(selectedModel);
      cancellation.throwIfCancelled();
      await _downloadWithProgress(selectedModel, stagingFile, cancellation);
      cancellation.throwIfCancelled();
      _publishPhase(ModelProvisioningPhase.verifying, model: selectedModel);
      await _integrityVerifier.verify(
        model: selectedModel,
        filePath: stagingFile.path,
      );
      cancellation.throwIfCancelled();
      _publishPhase(ModelProvisioningPhase.committing, model: selectedModel);
      final ModelStagingFile committedStagingFile = stagingFile;
      final String localPath = await _modelStorage.commitStagingFile(
        committedStagingFile,
      );
      stagingFile = null;
      await _saveReadinessBestEffort(
        _snapshot(
          model: selectedModel,
          capability: capability,
          status: ModelReadinessStatus.ready,
          localPath: localPath,
        ),
      );
      _publishPhase(ModelProvisioningPhase.artifactReady, model: selectedModel);
      return PreparedModel(
        selectedModel: selectedModel,
        localPath: localPath,
        capability: capability,
      );
    } on Object catch (error, stackTrace) {
      if (stagingFile != null) {
        await _discardStagingBestEffort(stagingFile);
      }

      if (error is ModelProvisioningCancelledException) {
        _publishCancelled(model: selectedModel);
        final DeviceCapability? detectedCapability = capability;
        if (selectedModel != null && detectedCapability != null) {
          await _saveReadinessBestEffort(
            _snapshot(
              model: selectedModel,
              capability: detectedCapability,
              status: ModelReadinessStatus.cancelled,
            ),
          );
        }
        Error.throwWithStackTrace(error, stackTrace);
      }

      if (selectedModel != null &&
          existingPath != null &&
          error is ModelIntegrityException) {
        await _discardModelBestEffort(selectedModel);
      }

      _publishFailure(error, model: selectedModel);
      final DeviceCapability? detectedCapability = capability;
      if (selectedModel != null && detectedCapability != null) {
        await _saveReadinessBestEffort(
          _snapshot(
            model: selectedModel,
            capability: detectedCapability,
            status: ModelReadinessStatus.failed,
            lastError: _boundedError(error),
          ),
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Downloads [model] into [stagingFile], publishing the downloading phase
  /// and cumulative byte progress when a reporter is present.
  Future<void> _downloadWithProgress(
    ModelDescriptor model,
    ModelStagingFile stagingFile,
    ModelProvisioningCancellationToken cancellation,
  ) async {
    if (_modelProvisioningReporter == null) {
      await _modelDownloader.download(
        model: model,
        target: stagingFile,
        cancellation: cancellation,
      );
      return;
    }

    // The declared artifact size is the authoritative known total: it is what
    // integrity verification enforces afterwards, so the download progress
    // bound is known from the descriptor even when the HTTP length is not.
    _publishPhase(
      ModelProvisioningPhase.downloading,
      model: model,
      totalBytes: model.fileSizeBytes,
    );
    await _modelDownloader.download(
      model: model,
      target: stagingFile,
      cancellation: cancellation,
      onProgress: (int receivedBytes) {
        _publishPhase(
          ModelProvisioningPhase.downloading,
          model: model,
          downloadedBytes: receivedBytes,
          totalBytes: model.fileSizeBytes,
        );
      },
    );
  }

  AiReadinessSnapshot _snapshot({
    required ModelDescriptor model,
    required DeviceCapability capability,
    required ModelReadinessStatus status,
    String? localPath,
    String? lastError,
  }) {
    return AiReadinessSnapshot(
      modelId: model.id,
      modelVersion: model.version,
      modelSha256: model.sha256,
      localPath: localPath,
      platform: capability.platform,
      osVersion: capability.osVersion,
      isPhysicalDevice: capability.isPhysicalDevice,
      supportedAbis: capability.supportedAbis,
      status: status,
      lastError: lastError,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  /// Publishes one phase snapshot when a reporter is present.
  ///
  /// Byte progress defaults to zero with a null [totalBytes] (indeterminate)
  /// for phases without byte semantics.
  void _publishPhase(
    ModelProvisioningPhase phase, {
    ModelDescriptor? model,
    int downloadedBytes = 0,
    int? totalBytes,
  }) {
    _publishState(
      ModelProvisioningState(
        phase: phase,
        modelId: model?.id,
        modelName: model?.fileName,
        downloadedBytes: downloadedBytes,
        totalBytes: totalBytes,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// Publishes a failed snapshot for [error] via [mapModelProvisioningFailure].
  void _publishFailure(Object error, {ModelDescriptor? model}) {
    _publishState(
      ModelProvisioningState(
        phase: ModelProvisioningPhase.failed,
        modelId: model?.id,
        modelName: model?.fileName,
        failure: mapModelProvisioningFailure(error),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  void _publishCancelled({ModelDescriptor? model}) {
    _publishState(
      ModelProvisioningState(
        phase: ModelProvisioningPhase.cancelled,
        modelId: model?.id,
        modelName: model?.fileName,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> _cleanupStagingBestEffort() async {
    try {
      await _modelStorage.cleanupStagingFiles();
    } on Object {
      // Recovery is best-effort. A cleanup failure must not block a fresh
      // provisioning attempt or replace its original error.
    }
  }

  Future<void> _discardModelBestEffort(ModelDescriptor model) async {
    try {
      await _modelStorage.discardModel(model);
    } on Object {
      // Never replace the integrity error with a recovery failure.
    }
  }

  /// Publishes [state] best-effort: reporting is advisory and must never
  /// change provisioning semantics or mask the original provisioning result.
  void _publishState(ModelProvisioningState state) {
    evidenceProvisioning(
      phase: state.phase.name,
      modelId: state.modelId,
      downloadedBytes: state.downloadedBytes,
      totalBytes: state.totalBytes,
    );
    final IModelProvisioningReporter? reporter = _modelProvisioningReporter;
    if (reporter == null) {
      return;
    }
    try {
      reporter.publish(state);
    } on Object {
      // A failing observer must not break detection, selection, download,
      // verification, commit, or the error observed by the caller.
    }
  }

  Future<void> _saveReadinessBestEffort(AiReadinessSnapshot snapshot) async {
    final AiConfigurationStore? store = _aiConfigurationStore;
    if (store == null) {
      return;
    }
    try {
      await store.save(snapshot);
    } on Object {
      // Readiness is advisory bookkeeping. A store failure must not hide a
      // successful model preparation or replace the original provisioning
      // error.
    }
  }

  static String _boundedError(Object error) {
    const int maxLength = 512;
    final String message = error.toString().replaceAll(RegExp(r'\s+'), ' ');
    if (message.length <= maxLength) {
      return message;
    }
    return '${message.substring(0, maxLength - 1)}…';
  }

  /// Discards only the staging file and never masks the original failure.
  Future<void> _discardStagingBestEffort(ModelStagingFile stagingFile) async {
    try {
      await _modelStorage.discardStagingFile(stagingFile);
    } on Object {
      // Cleanup is best-effort. The download, verification, or commit error
      // remains the error observed by the caller.
    }
  }
}
