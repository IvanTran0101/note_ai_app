/// Application-facing model-provisioning state boundary (M4.5.a).
///
/// This library owns the observable state of one model-provisioning attempt:
/// the lifecycle phases in [ModelProvisioningPhase] and the immutable,
/// primitive-first [ModelProvisioningState] snapshot that carries a phase,
/// optional model identity, byte progress, an optional terminal failure, and
/// the observation time. Progress invariants are validated at construction so
/// a reporting adapter cannot publish contradictory state.
///
/// The library is deliberately free of Flutter, `dart:io`, Domain, and
/// Infrastructure types, and it introduces no NoteId-style value objects: the
/// optional model identity is two plain strings. Domain contracts and existing
/// Application services are untouched by this boundary.
library;

import 'model_provisioning_failure.dart';

/// One observable step of the model-provisioning lifecycle.
///
/// Phases run in lifecycle order; [awaitingDownloadApproval] sits between
/// [checkingExistingModel] and [downloading]; [failed] and [cancelled] are
/// terminal non-success steps and [ready] is the terminal success step.
enum ModelProvisioningPhase {
  /// No provisioning attempt has started.
  idle,

  /// The app is reading the device capability (platform, OS, ABI, memory).
  detectingDevice,

  /// The best compatible catalog model is being chosen.
  selectingModel,

  /// The selected model's artifact is being looked up on this device.
  checkingExistingModel,

  /// The artifact is absent locally and the app is asking the user for
  /// permission to download it.
  ///
  /// Carries the selected model identity and the declared artifact size in
  /// [ModelProvisioningState.totalBytes] so a prompt can state what will be
  /// downloaded. It is only published when a download-approval callback is
  /// injected; without one, provisioning continues straight to [downloading]
  /// (legacy behavior).
  awaitingDownloadApproval,

  /// The artifact is being downloaded; byte progress applies here.
  downloading,

  /// The artifact is being verified against its size/SHA-256 metadata.
  verifying,

  /// The verified staging artifact is being moved into its final location.
  committing,

  /// The verified artifact is committed and ready to be loaded.
  artifactReady,

  /// The committed artifact is being loaded into the native runtime.
  loadingRuntime,

  /// Provisioning finished successfully; the model is usable.
  ready,

  /// The attempt ended in failure; the snapshot must carry the failure.
  failed,

  /// The user cancelled the active provisioning attempt.
  cancelled,
}

/// Immutable snapshot of one model-provisioning attempt at a point in time.
///
/// The value is primitive-first and fully immutable: every field is fixed at
/// construction and exposed read-only. [modelId] and [modelName] are optional
/// plain strings that stay null until a model has been identified;
/// [downloadedBytes] counts received artifact bytes and [totalBytes] is the
/// declared artifact size, or null when unknown (indeterminate progress).
/// [failure] is present exactly when [phase] is
/// [ModelProvisioningPhase.failed]. A cancelled attempt has no failure.
final class ModelProvisioningState {
  /// Creates a snapshot.
  ///
  /// Progress invariants are validated here: [downloadedBytes] must be
  /// non-negative, a present [totalBytes] must be positive and at least
  /// [downloadedBytes], and [failure] must be present exactly when [phase] is
  /// [ModelProvisioningPhase.failed]: it cannot be attached to any other
  /// phase, and the failed phase cannot omit it.
  ModelProvisioningState({
    this.phase = ModelProvisioningPhase.idle,
    this.modelId,
    this.modelName,
    this.downloadedBytes = 0,
    this.totalBytes,
    this.failure,
    required this.updatedAt,
  }) {
    if (downloadedBytes < 0) {
      throw ArgumentError.value(
        downloadedBytes,
        'downloadedBytes',
        'must not be negative',
      );
    }
    final int? total = totalBytes;
    if (total != null) {
      if (total <= 0) {
        throw ArgumentError.value(
          total,
          'totalBytes',
          'must be greater than zero',
        );
      }
      if (downloadedBytes > total) {
        throw ArgumentError.value(
          downloadedBytes,
          'downloadedBytes',
          'must not exceed totalBytes ($total)',
        );
      }
    }
    if (failure != null && phase != ModelProvisioningPhase.failed) {
      throw ArgumentError.value(
        phase,
        'phase',
        'a failure may only be attached to the failed phase',
      );
    }
    if (phase == ModelProvisioningPhase.failed && failure == null) {
      throw ArgumentError.value(
        phase,
        'phase',
        'the failed phase requires a failure',
      );
    }
  }

  /// The lifecycle step this snapshot describes.
  final ModelProvisioningPhase phase;

  /// Catalog identifier of the model being provisioned, or null until one is
  /// selected (e.g. `gemma-3-1b-it`).
  final String? modelId;

  /// Display name of the model being provisioned, or null until one is
  /// selected. Carries only user-presentable text.
  final String? modelName;

  /// Artifact bytes received so far. Always non-negative.
  final int downloadedBytes;

  /// Declared artifact size in bytes, or null when unknown.
  ///
  /// A null [totalBytes] means the byte progress is indeterminate: no fraction
  /// can be computed because no bound is known (unknown download length, or a
  /// phase without byte-progress semantics such as verification or runtime
  /// loading).
  final int? totalBytes;

  /// The failure that ended the attempt, present exactly when [phase] is
  /// [ModelProvisioningPhase.failed].
  final ModelProvisioningFailure? failure;

  /// When this snapshot was observed (UTC by convention).
  final DateTime updatedAt;

  /// True when [totalBytes] is null, so no determinate fraction can be
  /// derived from [downloadedBytes].
  bool get isIndeterminate => totalBytes == null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ModelProvisioningState &&
        other.phase == phase &&
        other.modelId == modelId &&
        other.modelName == modelName &&
        other.downloadedBytes == downloadedBytes &&
        other.totalBytes == totalBytes &&
        other.failure == failure &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    phase,
    modelId,
    modelName,
    downloadedBytes,
    totalBytes,
    failure,
    updatedAt,
  );

  @override
  String toString() {
    return 'ModelProvisioningState(phase: ${phase.name}, modelId: $modelId, '
        'modelName: $modelName, downloadedBytes: $downloadedBytes, '
        'totalBytes: $totalBytes, '
        'failure: ${failure?.code.name ?? 'none'}, updatedAt: $updatedAt)';
  }
}
