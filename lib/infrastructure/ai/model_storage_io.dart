/// [IModelStorage] implementation for iOS and Android (and any other
/// `dart:io` platform).
///
/// Resolves GGUF models at `<app support>/models/<fileName>` using
/// `path_provider`'s [getApplicationSupportDirectory] by default. The
/// directory resolver is injectable so unit tests run without a plugin
/// channel. A macOS debug build can pass [LocalModelStorage.overrideModelPath]
/// (e.g. an absolute path driven by a `--dart-define` in the entrypoint) to
/// bypass the app-support layout entirely; the override pins the single
/// on-device model for both [resolveModelPath] and [findModel].
///
/// This library never loads the model or the local LLM runtime, and never
/// downloads an artifact; it only validates existence and returns a file path.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'model_selection.dart';
import 'model_storage_contract.dart';

/// Factory matching the Web stub's signature. On `dart:io` platforms it
/// returns a real [LocalModelStorage].
IModelStorage createModelStorage({
  String? overrideModelPath,
  AppSupportDirectoryResolver? appSupportDirectoryPath,
}) {
  return LocalModelStorage(
    overrideModelPath: overrideModelPath,
    appSupportDirectoryPath: appSupportDirectoryPath,
  );
}

/// Resolves GGUF files under `<app support>/models/`.
final class LocalModelStorage implements IModelStorage {
  /// [overrideModelPath] skips the app-support layout and pins the model to an
  /// explicit absolute path — the macOS debug escape hatch. When null models
  /// are located at `<app support>/models/<fileName>`.
  ///
  /// [appSupportDirectoryPath] overrides the default
  /// [getApplicationSupportDirectory] lookup (used by unit tests).
  LocalModelStorage({
    String? overrideModelPath,
    AppSupportDirectoryResolver? appSupportDirectoryPath,
  }) : overrideModelPath = _normalizeOverride(overrideModelPath),
       appSupportDirectoryPath =
           appSupportDirectoryPath ?? _defaultAppSupportDirectoryPath;

  static String? _normalizeOverride(String? path) {
    final String? trimmed = path?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static Future<String> _defaultAppSupportDirectoryPath() async {
    final Directory directory = await getApplicationSupportDirectory();
    return directory.path;
  }

  /// The explicit model path pin, or null to resolve the app-support layout.
  final String? overrideModelPath;

  /// Resolver of the application support directory (injectable for tests).
  final AppSupportDirectoryResolver appSupportDirectoryPath;

  @override
  Future<String> resolveModelPath() async {
    final String candidate = await _resolveCandidatePath(kModelFileName);
    if (!await _exists(candidate)) {
      throw ModelNotFoundException(candidate);
    }
    return File(candidate).absolute.path;
  }

  @override
  Future<String?> findModel(ModelDescriptor model) async {
    final String candidate = await _resolveCandidatePath(model.fileName);
    if (!await _exists(candidate)) {
      return null;
    }
    return File(candidate).absolute.path;
  }

  /// Computes the candidate path for [fileName]: the pinned override when set,
  /// otherwise `<app support>/models/<fileName>`.
  Future<String> _resolveCandidatePath(String fileName) async {
    _validateFileName(fileName);
    final String? override = overrideModelPath;
    if (override != null) {
      return override;
    }
    final String supportPath;
    try {
      supportPath = await appSupportDirectoryPath();
    } on Object catch (error) {
      throw ModelStorageException(
        'failed to resolve the application support directory: $error',
      );
    }
    return <String>[
      supportPath,
      kModelDirectoryName,
      fileName,
    ].join(Platform.pathSeparator);
  }

  /// Storage may validate paths: a model file name must be a bare file name so
  /// a catalog bug cannot escape the models directory.
  static void _validateFileName(String fileName) {
    final String trimmed = fileName.trim();
    if (trimmed.isEmpty) {
      throw const ModelStorageException('model fileName must not be empty');
    }
    if (trimmed == '.' ||
        trimmed == '..' ||
        trimmed.contains('/') ||
        trimmed.contains(r'\')) {
      throw ModelStorageException(
        'model fileName must be a bare file name, got: $trimmed',
      );
    }
  }

  static Future<bool> _exists(String candidate) async {
    try {
      return await File(candidate).exists();
    } on Object catch (error) {
      throw ModelStorageException('failed to check model file: $error');
    }
  }
}
