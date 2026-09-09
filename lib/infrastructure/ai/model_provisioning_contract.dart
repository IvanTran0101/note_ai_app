/// Contracts shared by model provisioning infrastructure.
///
/// This library intentionally contains only platform-neutral data and
/// interfaces. It does not know how to download bytes, calculate a digest,
/// access the filesystem, or load the local LLM runtime.
library;

import 'model_selection.dart';
import '../device/hardware_detection.dart';

/// A temporary file allocated for one selected model.
///
/// The storage implementation owns the staging path. The downloader writes
/// only to this path, and the manager asks storage to atomically commit or
/// discard it after the download and integrity checks complete.
final class ModelStagingFile {
  /// Creates a staging-file reference for [model] at [path].
  const ModelStagingFile({required this.model, required this.path});

  /// The model whose bytes are being staged.
  final ModelDescriptor model;

  /// Absolute path allocated by model storage for the temporary artifact.
  final String path;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ModelStagingFile && other.model == model && other.path == path;
  }

  @override
  int get hashCode => Object.hash(model, path);

  @override
  String toString() => 'ModelStagingFile(model: $model.id, path: $path)';
}

/// Source of model descriptors available for this application build.
///
/// The catalog is metadata only. It does not download or validate any model.
abstract interface class IModelCatalog {
  /// Candidate descriptors in deterministic catalog order.
  List<ModelDescriptor> get models;
}

/// Reports cumulative artifact bytes received so far for one download.
///
/// [receivedBytes] is monotonic (never decreases), is at most the selected
/// model's declared [ModelDescriptor.fileSizeBytes], and equals the full
/// artifact size when the download finishes. Progress reporting is optional
/// and advisory: an implementation must never require a listener.
typedef ModelDownloadProgress = void Function(int receivedBytes);

/// Writes exactly one selected model to a storage-provided staging file.
abstract interface class IModelDownloader {
  /// Downloads [model] into [target].
  ///
  /// Implementations should fail without publishing a final model path. The
  /// manager discards [target] when this operation or a later staging step
  /// fails.
  ///
  /// When [onProgress] is supplied, the implementation calls it with the
  /// cumulative number of artifact bytes received so far after each chunk
  /// (never with a negative or decreasing value, never beyond the model's
  /// declared size). A null [onProgress] means the caller does not observe
  /// progress.
  Future<void> download({
    required ModelDescriptor model,
    required ModelStagingFile target,
    ModelDownloadProgress? onProgress,
  });
}

/// Verifies a model artifact without deciding how it is stored or loaded.
abstract interface class IModelIntegrityVerifier {
  /// Verifies [filePath] against the metadata in [model].
  ///
  /// The concrete digest algorithm and implementation are intentionally
  /// outside this slice.
  Future<void> verify({
    required ModelDescriptor model,
    required String filePath,
  });
}

/// Orchestrates detection, selection, local lookup, staging, and publication
/// of one model artifact.
abstract interface class IModelManager {
  /// Ensures the selected model is available as a verified local file.
  Future<PreparedModel> ensureModelReady();
}

/// Result returned after one model has been selected and integrity-verified.
final class PreparedModel {
  /// Creates a prepared-model result.
  const PreparedModel({
    required this.selectedModel,
    required this.localPath,
    required this.capability,
  });

  /// The one descriptor selected for the detected device.
  final ModelDescriptor selectedModel;

  /// Absolute path to the verified, publishable local model file.
  final String localPath;

  /// Capability snapshot used to select [selectedModel].
  final DeviceCapability capability;

  /// Alias useful to callers that refer to the descriptor as the model.
  ModelDescriptor get model => selectedModel;

  /// Alias useful to callers that refer to the prepared file as its path.
  String get path => localPath;

  /// Explicit name for the capability snapshot returned with the result.
  DeviceCapability get detectedCapability => capability;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PreparedModel &&
            other.selectedModel == selectedModel &&
            other.localPath == localPath &&
            other.capability == capability;
  }

  @override
  int get hashCode => Object.hash(selectedModel, localPath, capability);

  @override
  String toString() {
    return 'PreparedModel(model: $selectedModel.id, path: $localPath, '
        'capability: $capability)';
  }
}

/// Raised when the selection policy cannot select any catalog candidate.
final class NoModelSelectedException implements Exception {
  /// Creates an exception containing the capability and policy result that
  /// explain why provisioning cannot continue.
  const NoModelSelectedException({
    required this.capability,
    required this.selection,
  });

  /// Device snapshot used by the failed selection.
  final DeviceCapability capability;

  /// Full policy result, including per-candidate rejection reasons.
  final ModelSelectionResult selection;

  /// A concise human-readable explanation suitable for logs or UI mapping.
  String get message {
    final String reasons = selection.rejectionReasons.isEmpty
        ? ''
        : ' Rejections: ${selection.rejectionReasons}.';
    return 'No compatible model was selected for ${capability.platform} '
        '${capability.osVersion}.$reasons';
  }

  @override
  String toString() => 'NoModelSelectedException: $message';
}

/// Typed failure raised when a model artifact cannot be downloaded safely.
///
/// Declared in this platform-neutral contract (rather than only in the native
/// and Web implementations) so platform-neutral orchestrators such as the
/// model manager can map it onto the Application failure vocabulary.
final class ModelDownloadException implements Exception {
  /// Creates a download failure with a human-readable explanation.
  const ModelDownloadException(this.message);

  /// Explanation suitable for logs or application error mapping.
  final String message;

  @override
  String toString() => 'ModelDownloadException: $message';
}

/// Typed failure raised when a model artifact fails integrity validation.
///
/// Declared in this platform-neutral contract so platform-neutral
/// orchestrators can map it onto the Application failure vocabulary without
/// depending on a native or Web implementation.
final class ModelIntegrityException implements Exception {
  /// Creates an integrity failure with a human-readable explanation.
  const ModelIntegrityException(this.message);

  /// Explanation suitable for logs or application error mapping.
  final String message;

  @override
  String toString() => 'ModelIntegrityException: $message';
}
