/// Public entrypoint for the persisted AI configuration store.
///
/// On platforms with `dart:io` this resolves to the path_provider-backed
/// implementation (`ai_configuration_store_io.dart`). On the Web — where
/// `dart:io` and `path_provider` are unavailable — it resolves to
/// `ai_configuration_store_stub.dart`, whose [createAiConfigurationStore]
/// returns a store that throws [UnsupportedError]. The store only persists
/// model-readiness bookkeeping; it never validates the model file.
library;

export 'ai_configuration_store_contract.dart';

export 'ai_configuration_store_stub.dart'
    if (dart.library.io) 'ai_configuration_store_io.dart';
