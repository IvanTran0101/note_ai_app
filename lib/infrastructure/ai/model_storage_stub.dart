/// Web-safe unavailable implementation of [IModelStorage].
///
/// `dart:io` and `path_provider` are unavailable on the Web, so this library
/// imports neither. [createModelStorage] returns an [UnavailableModelStorage]
/// so Web builds compile and start; every [resolveModelPath] and [findModel]
/// call throws [UnsupportedError]. There is deliberately NO fake model path on
/// the Web.
library;

import 'model_selection.dart';
import 'model_provisioning_contract.dart';
import 'model_storage_contract.dart';

/// A storage that is never usable: the Web has no local GGUF file.
final class UnavailableModelStorage implements IModelStorage {
  const UnavailableModelStorage();

  @override
  Future<String> resolveModelPath() {
    throw UnsupportedError(
      'Local model storage is not available on this platform (Web). '
      'Serve the model through a separate remote inference path.',
    );
  }

  @override
  Future<String?> findModel(ModelDescriptor model) {
    throw UnsupportedError(
      'Local model storage is not available on this platform (Web). '
      'Serve the model through a separate remote inference path.',
    );
  }

  @override
  Future<ModelStagingFile> createStagingFile(ModelDescriptor model) {
    throw UnsupportedError(
      'Local model storage is not available on this platform (Web). '
      'Serve the model through a separate remote inference path.',
    );
  }

  @override
  Future<String> commitStagingFile(ModelStagingFile stagingFile) {
    throw UnsupportedError(
      'Local model storage is not available on this platform (Web). '
      'Serve the model through a separate remote inference path.',
    );
  }

  @override
  Future<void> discardStagingFile(ModelStagingFile stagingFile) {
    throw UnsupportedError(
      'Local model storage is not available on this platform (Web). '
      'Serve the model through a separate remote inference path.',
    );
  }

  @override
  Future<int> cleanupStagingFiles({
    Duration olderThan = const Duration(hours: 24),
  }) {
    throw UnsupportedError(
      'Local model storage is not available on this platform (Web).',
    );
  }

  @override
  Future<void> discardModel(ModelDescriptor model) {
    throw UnsupportedError(
      'Local model storage is not available on this platform (Web).',
    );
  }
}

/// Returns an [UnavailableModelStorage] on platforms without local model
/// storage (Web). The signature matches the `dart:io` factory.
IModelStorage createModelStorage({
  String? overrideModelPath,
  AppSupportDirectoryResolver? appSupportDirectoryPath,
}) {
  return const UnavailableModelStorage();
}
