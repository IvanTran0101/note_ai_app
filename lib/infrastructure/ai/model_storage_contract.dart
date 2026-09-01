/// Platform-neutral contract for locating on-device GGUF model files.
///
/// This library must stay free of `dart:io`, `package:path_provider`, and
/// `package:local_llm_bridge` so it compiles on the Web. The native
/// implementation lives behind a conditional import in `model_storage.dart`;
/// on Web the stub's methods throw [UnsupportedError] — Web never fakes a
/// model path. Storage only validates existence and returns absolute file
/// paths; it never downloads a model or loads a runtime.
library;

import 'model_selection.dart';
import 'model_provisioning_contract.dart';

/// The directory (relative to the app support directory) that holds GGUF
/// models on iOS and Android.
const String kModelDirectoryName = 'models';

/// The Gemma 3 1B instruction-tuned Q4_K_M GGUF artifact this app uses.
///
/// Kept for the legacy [IModelStorage.resolveModelPath] entrypoint; model-aware
/// callers locate a specific artifact via [IModelStorage.findModel].
const String kModelFileName = 'gemma-3-1b-it-Q4_K_M.gguf';

/// Resolves the application support directory (as an absolute path string).
///
/// Kept as a plain `String`-returning function so the contract stays free of
/// `dart:io` types and can be injected in unit tests without a device or the
/// `path_provider` plugin channel.
typedef AppSupportDirectoryResolver = Future<String> Function();

/// Locates on-device GGUF model files.
///
/// Implementations only validate existence and return absolute file paths;
/// they never load the model, download anything, or touch the local LLM
/// runtime.
abstract interface class IModelStorage {
  /// Returns the absolute path to the default Gemma GGUF model file if it
  /// exists.
  ///
  /// Throws [ModelNotFoundException] when the model is not present at the
  /// resolved location, and [ModelStorageException] for other storage
  /// failures (e.g. the app support directory cannot be resolved).
  Future<String> resolveModelPath();

  /// Returns the absolute path to the on-device file for [model] if it exists,
  /// or null when the model file is not present at the resolved location.
  ///
  /// The file name is taken from [ModelDescriptor.fileName] and resolved under
  /// the model directory; the descriptor's download and runtime metadata are
  /// never used here. Throws [ModelStorageException] for other storage
  /// failures (e.g. the app support directory cannot be resolved, or
  /// [ModelDescriptor.fileName] is not a bare file name). Implementations
  /// never download the artifact or load a runtime.
  Future<String?> findModel(ModelDescriptor model);

  /// Creates an empty, uniquely named staging file for [model] under the
  /// app-private model directory.
  ///
  /// The returned handle is the only supported input to
  /// [commitStagingFile] and [discardStagingFile]. An explicit debug model
  /// path override is intentionally rejected: staging must always happen in
  /// the app-private directory so a later commit cannot move or delete an
  /// arbitrary external file.
  Future<ModelStagingFile> createStagingFile(ModelDescriptor model);

  /// Atomically moves [stagingFile] to the model's final bare file name.
  ///
  /// The destination is never overwritten. Implementations reject a missing,
  /// foreign, malformed, or otherwise untrusted staging path.
  Future<String> commitStagingFile(ModelStagingFile stagingFile);

  /// Removes [stagingFile] when it is a validated app-private staging file.
  ///
  /// Implementations must never use this operation to delete the explicit
  /// debug override or an arbitrary path outside the model directory.
  Future<void> discardStagingFile(ModelStagingFile stagingFile);
}

/// Base error for model storage failures other than a missing model.
final class ModelStorageException implements Exception {
  const ModelStorageException(this.message);

  final String message;

  @override
  String toString() => 'ModelStorageException: $message';
}

/// The model file does not exist at the resolved location.
final class ModelNotFoundException extends ModelStorageException {
  const ModelNotFoundException(super.message);

  @override
  String toString() => 'ModelNotFoundException: $message';
}
