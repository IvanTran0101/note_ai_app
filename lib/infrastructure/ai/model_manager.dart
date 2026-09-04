/// Single-model provisioning orchestration with advisory readiness state
/// (M3.3a/M4.4).
///
/// This class coordinates the infrastructure contracts only. It does not
/// contain a model catalog, download implementation, digest implementation,
/// platform detection implementation, or local LLM runtime code.
library;

import 'dart:async';

import '../configuration/ai_configuration_store.dart';
import '../device/hardware_detection.dart';
import 'model_provisioning_contract.dart';
import 'model_selection.dart';
import 'model_storage_contract.dart';

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
  ModelManager({
    required IHardwareDetectionService hardwareDetectionService,
    required IModelSelectionPolicy modelSelectionPolicy,
    required IModelCatalog modelCatalog,
    required IModelStorage modelStorage,
    required IModelDownloader modelDownloader,
    required IModelIntegrityVerifier integrityVerifier,
    AiConfigurationStore? aiConfigurationStore,
  }) : this._(
         hardwareDetectionService,
         modelSelectionPolicy,
         modelCatalog,
         modelStorage,
         modelDownloader,
         integrityVerifier,
         aiConfigurationStore,
       );

  ModelManager._(
    this._hardwareDetectionService,
    this._modelSelectionPolicy,
    this._modelCatalog,
    this._modelStorage,
    this._modelDownloader,
    this._integrityVerifier,
    this._aiConfigurationStore,
  );

  final IHardwareDetectionService _hardwareDetectionService;
  final IModelSelectionPolicy _modelSelectionPolicy;
  final IModelCatalog _modelCatalog;
  final IModelStorage _modelStorage;
  final IModelDownloader _modelDownloader;
  final IModelIntegrityVerifier _integrityVerifier;
  final AiConfigurationStore? _aiConfigurationStore;

  /// The current provisioning operation, if one is already running.
  Future<PreparedModel>? _inFlight;

  /// Returns the current operation when present; otherwise starts exactly one
  /// operation and shares it with concurrent callers.
  @override
  Future<PreparedModel> ensureModelReady() {
    final Future<PreparedModel>? current = _inFlight;
    if (current != null) {
      return current;
    }

    final Future<PreparedModel> started = _prepareModel();
    _inFlight = started;

    // Clear the guard after either success or failure. The derived future
    // intentionally handles the error so it cannot become an unhandled error;
    // the original future returned to the caller retains the original error.
    unawaited(
      started.then<void>(
        (_) => _clearInFlight(started),
        onError: (Object error, StackTrace stackTrace) {
          _clearInFlight(started);
        },
      ),
    );

    return started;
  }

  Future<void> _clearInFlight(Future<PreparedModel> operation) async {
    if (identical(_inFlight, operation)) {
      _inFlight = null;
    }
  }

  Future<PreparedModel> _prepareModel() async {
    final DeviceCapability capability = await _hardwareDetectionService
        .getDeviceCapability();
    final ModelSelectionResult selection = _modelSelectionPolicy.select(
      capability: capability,
      candidates: _modelCatalog.models,
    );
    final ModelDescriptor? selectedModel = selection.selectedModel;
    if (selectedModel == null) {
      throw NoModelSelectedException(
        capability: capability,
        selection: selection,
      );
    }

    await _saveReadinessBestEffort(
      _snapshot(
        model: selectedModel,
        capability: capability,
        status: ModelReadinessStatus.preparing,
      ),
    );

    ModelStagingFile? stagingFile;
    try {
      final String? existingPath = await _modelStorage.findModel(selectedModel);
      if (existingPath != null) {
        // This branch intentionally has no staging cleanup: a verifier failure
        // must not delete or discard an already-existing model.
        await _integrityVerifier.verify(
          model: selectedModel,
          filePath: existingPath,
        );
        await _saveReadinessBestEffort(
          _snapshot(
            model: selectedModel,
            capability: capability,
            status: ModelReadinessStatus.ready,
            localPath: existingPath,
          ),
        );
        return PreparedModel(
          selectedModel: selectedModel,
          localPath: existingPath,
          capability: capability,
        );
      }

      stagingFile = await _modelStorage.createStagingFile(selectedModel);
      await _modelDownloader.download(
        model: selectedModel,
        target: stagingFile,
      );
      await _integrityVerifier.verify(
        model: selectedModel,
        filePath: stagingFile.path,
      );
      final String localPath = await _modelStorage.commitStagingFile(
        stagingFile,
      );
      await _saveReadinessBestEffort(
        _snapshot(
          model: selectedModel,
          capability: capability,
          status: ModelReadinessStatus.ready,
          localPath: localPath,
        ),
      );
      return PreparedModel(
        selectedModel: selectedModel,
        localPath: localPath,
        capability: capability,
      );
    } on Object catch (error, stackTrace) {
      if (stagingFile != null) {
        await _discardStagingBestEffort(stagingFile);
      }
      await _saveReadinessBestEffort(
        _snapshot(
          model: selectedModel,
          capability: capability,
          status: ModelReadinessStatus.failed,
          lastError: _boundedError(error),
        ),
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
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
