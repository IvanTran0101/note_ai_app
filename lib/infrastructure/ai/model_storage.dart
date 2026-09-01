/// Public entrypoint for on-device model storage.
///
/// On platforms with `dart:io` this resolves to the path_provider-backed
/// implementation (`model_storage_io.dart`). On the Web — where `dart:io` and
/// `path_provider` are unavailable — it resolves to `model_storage_stub.dart`,
/// whose [createModelStorage] returns an [UnavailableModelStorage] that throws
/// [UnsupportedError]. Model storage never loads the local LLM runtime; it
/// only validates and returns a file path.
library;

export 'model_storage_contract.dart';

export 'model_storage_stub.dart' if (dart.library.io) 'model_storage_io.dart';
