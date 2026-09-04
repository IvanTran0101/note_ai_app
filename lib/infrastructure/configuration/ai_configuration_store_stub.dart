/// Web-safe unavailable implementation of [AiConfigurationStore].
///
/// `dart:io` and `path_provider` are unavailable on the Web, so this library
/// imports neither. [createAiConfigurationStore] returns a
/// [FileAiConfigurationStore] so Web builds compile and start; every [read],
/// [save], and [clear] call throws [UnsupportedError]. There is deliberately
/// NO fake persisted readiness state on the Web.
library;

import 'ai_configuration_store_contract.dart';

/// A store that is never usable: the Web has no app-private native file for
/// model-readiness state. The class name and constructor match the native
/// implementation so the conditional facade can swap them by platform.
final class FileAiConfigurationStore implements AiConfigurationStore {
  /// Constructor signature matches the native implementation; the resolver is
  /// accepted and ignored because no file is ever read or written.
  FileAiConfigurationStore({
    ApplicationSupportPathResolver? applicationSupportPathResolver,
  });

  @override
  Future<AiReadinessSnapshot?> read() {
    throw UnsupportedError(
      'The AI configuration store is not available on this platform (Web). '
      'Model readiness is not persisted on the Web.',
    );
  }

  @override
  Future<void> save(AiReadinessSnapshot snapshot) {
    throw UnsupportedError(
      'The AI configuration store is not available on this platform (Web). '
      'Model readiness is not persisted on the Web.',
    );
  }

  @override
  Future<void> clear() {
    throw UnsupportedError(
      'The AI configuration store is not available on this platform (Web). '
      'Model readiness is not persisted on the Web.',
    );
  }
}

/// Returns an unavailable [FileAiConfigurationStore] on platforms without a
/// native filesystem store (Web). The signature matches the `dart:io` factory.
AiConfigurationStore createAiConfigurationStore({
  ApplicationSupportPathResolver? applicationSupportPathResolver,
}) {
  return FileAiConfigurationStore(
    applicationSupportPathResolver: applicationSupportPathResolver,
  );
}
