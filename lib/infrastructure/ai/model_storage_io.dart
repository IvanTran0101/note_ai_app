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
import 'dart:async';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import 'model_provisioning_contract.dart';
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

  /// Staging mutations are serialized per storage instance. This keeps the
  /// existence check and the subsequent atomic rename from racing with
  /// another provisioning operation in the same process.
  Future<void> _stagingOperationTail = Future<void>.value();

  /// Handles issued by this storage instance, keyed by their normalized path.
  /// Keeping the descriptor alongside the path prevents a caller from taking
  /// a valid staging path and pairing it with a different model descriptor.
  final Map<String, ModelDescriptor> _issuedStagingFiles =
      <String, ModelDescriptor>{};

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

  @override
  Future<ModelStagingFile> createStagingFile(ModelDescriptor model) {
    return _withStagingLock(() async {
      _rejectOverrideForStaging();
      _validateFileName(model.fileName);

      final Directory modelsDirectory = await _resolveModelsDirectory(
        create: true,
      );
      for (var attempt = 0; attempt < 8; attempt++) {
        final String candidate = _join(
          modelsDirectory.path,
          _stagingFileName(model.fileName),
        );
        final File file = File(candidate);
        try {
          await file.create(exclusive: true);
          final String absolutePath = _normalizeAbsolutePath(file.path);
          _issuedStagingFiles[absolutePath] = model;
          return ModelStagingFile(model: model, path: absolutePath);
        } on FileSystemException catch (error) {
          if (await file.exists()) {
            continue;
          }
          throw ModelStorageException(
            'failed to create model staging file: $error',
          );
        }
      }
      throw const ModelStorageException(
        'failed to allocate a unique model staging file',
      );
    });
  }

  @override
  Future<String> commitStagingFile(ModelStagingFile stagingFile) {
    return _withStagingLock(() async {
      _rejectOverrideForStaging();
      final _ValidatedStagingPaths paths = await _validateStagingFile(
        stagingFile,
      );

      final ModelDescriptor? issuedModel =
          _issuedStagingFiles[paths.stagingPath];
      if (issuedModel == null || issuedModel != stagingFile.model) {
        throw const ModelStorageException(
          'staging file was not issued for this exact model by this storage',
        );
      }

      final File staging = File(paths.stagingPath);
      if (!await _isRegularFile(staging)) {
        throw ModelNotFoundException(paths.stagingPath);
      }
      if (await File(paths.finalPath).exists()) {
        throw ModelStorageException(
          'final model already exists and will not be overwritten: '
          '${paths.finalPath}',
        );
      }

      try {
        // File.rename maps to the platform's rename operation, which is an
        // atomic move on the app's local filesystem. The serialized operation
        // queue plus the destination check prevents in-process overwrites.
        await staging.rename(paths.finalPath);
      } on FileSystemException catch (error) {
        throw ModelStorageException(
          'failed to commit model staging file: $error',
        );
      }
      _issuedStagingFiles.remove(paths.stagingPath);
      return _normalizeAbsolutePath(paths.finalPath);
    });
  }

  @override
  Future<void> discardStagingFile(ModelStagingFile stagingFile) {
    return _withStagingLock(() async {
      _rejectOverrideForStaging();
      final _ValidatedStagingPaths paths = await _validateStagingFile(
        stagingFile,
      );

      final File staging = File(paths.stagingPath);
      if (!await _isRegularFile(staging)) {
        // Discard is intentionally idempotent after a failed/finished
        // operation, but validation above still rejects foreign paths.
        _issuedStagingFiles.remove(paths.stagingPath);
        return;
      }
      try {
        await staging.delete();
      } on FileSystemException catch (error) {
        throw ModelStorageException(
          'failed to discard model staging file: $error',
        );
      }
      _issuedStagingFiles.remove(paths.stagingPath);
    });
  }

  @override
  Future<int> cleanupStagingFiles({
    Duration olderThan = const Duration(hours: 24),
  }) {
    if (olderThan.isNegative) {
      throw ArgumentError.value(olderThan, 'olderThan', 'must not be negative');
    }
    return _withStagingLock(() async {
      if (overrideModelPath != null) {
        return 0;
      }
      final Directory directory = await _resolveModelsDirectory(create: false);
      if (!await directory.exists()) {
        return 0;
      }

      final DateTime cutoff = DateTime.now().subtract(olderThan);
      var removed = 0;
      await for (final FileSystemEntity entity in directory.list(
        followLinks: false,
      )) {
        if (await FileSystemEntity.type(entity.path, followLinks: false) !=
            FileSystemEntityType.file) {
          continue;
        }
        final String name = _basename(entity.path);
        if (!_isRecognizedStagingName(name)) {
          continue;
        }
        final File file = File(entity.path);
        final FileStat stat;
        try {
          stat = await file.stat();
        } on Object {
          continue;
        }
        if (stat.modified.isAfter(cutoff)) {
          continue;
        }
        try {
          await file.delete();
          removed++;
        } on FileSystemException {
          // A single stale file must not prevent the next model attempt from
          // proceeding; the next cleanup can retry it.
        }
      }
      return removed;
    });
  }

  @override
  Future<void> discardModel(ModelDescriptor model) {
    return _withStagingLock(() async {
      if (overrideModelPath != null) {
        return;
      }
      _validateFileName(model.fileName);
      final Directory modelsDirectory = await _resolveModelsDirectory(
        create: false,
      );
      final String modelsPath = _normalizeAbsolutePath(modelsDirectory.path);
      final String finalPath = _normalizeAbsolutePath(
        _join(modelsPath, model.fileName),
      );
      if (_normalizeAbsolutePath(File(finalPath).parent.path) != modelsPath) {
        throw const ModelStorageException(
          'model recovery path must remain inside the app-private model directory',
        );
      }
      if (await FileSystemEntity.type(finalPath, followLinks: false) ==
          FileSystemEntityType.notFound) {
        return;
      }
      if (await FileSystemEntity.type(finalPath, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const ModelStorageException(
          'model recovery target is not a regular file',
        );
      }
      try {
        await File(finalPath).delete();
      } on FileSystemException catch (error) {
        throw ModelStorageException(
          'failed to discard the invalid model artifact: $error',
        );
      }
    });
  }

  /// Computes the candidate path for [fileName]: the pinned override when set,
  /// otherwise `<app support>/models/<fileName>`.
  Future<String> _resolveCandidatePath(String fileName) async {
    _validateFileName(fileName);
    final String? override = overrideModelPath;
    if (override != null) {
      return override;
    }
    final Directory modelsDirectory = await _resolveModelsDirectory(
      create: false,
    );
    return _join(modelsDirectory.path, fileName);
  }

  Future<Directory> _resolveModelsDirectory({required bool create}) async {
    final String supportPath;
    try {
      supportPath = await appSupportDirectoryPath();
    } on Object catch (error) {
      throw ModelStorageException(
        'failed to resolve the application support directory: $error',
      );
    }
    final Directory directory = Directory(
      _join(supportPath, kModelDirectoryName),
    );
    if (create) {
      try {
        await directory.create(recursive: true);
      } on FileSystemException catch (error) {
        throw ModelStorageException(
          'failed to create the model directory: $error',
        );
      }
    }
    return directory;
  }

  Future<_ValidatedStagingPaths> _validateStagingFile(
    ModelStagingFile stagingFile,
  ) async {
    _validateFileName(stagingFile.model.fileName);
    final Directory modelsDirectory = await _resolveModelsDirectory(
      create: false,
    );
    final String modelsPath = _normalizeAbsolutePath(modelsDirectory.path);
    final String stagingPath = _normalizeAbsolutePath(stagingFile.path);
    final String stagingParent = _normalizeAbsolutePath(
      File(stagingPath).parent.path,
    );
    final String stagingName = _basename(stagingPath);
    final String expectedPrefix = '${stagingFile.model.fileName}.';

    if (stagingParent != modelsPath ||
        !stagingName.startsWith(expectedPrefix) ||
        !stagingName.endsWith('.part') ||
        stagingName.length <= expectedPrefix.length + '.part'.length) {
      throw const ModelStorageException(
        'staging path must be a uniquely named .part file directly under '
        'the app-private model directory',
      );
    }

    final String finalPath = _join(modelsPath, stagingFile.model.fileName);
    return _ValidatedStagingPaths(
      stagingPath: stagingPath,
      finalPath: _normalizeAbsolutePath(finalPath),
    );
  }

  void _rejectOverrideForStaging() {
    if (overrideModelPath != null) {
      throw const ModelStorageException(
        'model staging is unavailable while an explicit model path override '
        'is configured',
      );
    }
  }

  Future<T> _withStagingLock<T>(Future<T> Function() action) {
    final Future<void> previous = _stagingOperationTail;
    final Completer<void> release = Completer<void>();
    _stagingOperationTail = release.future;
    return previous.then((_) async {
      try {
        return await action();
      } finally {
        release.complete();
      }
    });
  }

  static String _stagingFileName(String fileName) {
    final int timestamp = DateTime.now().microsecondsSinceEpoch;
    final int random = _random.nextInt(1 << 32);
    return '$fileName.$timestamp-$random.part';
  }

  static bool _isRecognizedStagingName(String name) {
    return RegExp(r'^.+\.\d+-\d+\.part$').hasMatch(name);
  }

  static String _join(String parent, String child) {
    return <String>[parent, child].join(Platform.pathSeparator);
  }

  static String _basename(String path) {
    final int separator = path.lastIndexOf(Platform.pathSeparator);
    return separator == -1 ? path : path.substring(separator + 1);
  }

  static String _normalizeAbsolutePath(String path) {
    final String absolute = File(path).absolute.path;
    final String separator = Platform.pathSeparator;
    final bool rooted = absolute.startsWith(separator);
    final List<String> segments = <String>[];
    for (final String segment in absolute.split(separator)) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..') {
        if (segments.isNotEmpty && segments.last != '..') {
          segments.removeLast();
        }
        continue;
      }
      segments.add(segment);
    }
    final String joined = segments.join(separator);
    if (rooted) {
      return '$separator$joined';
    }
    return joined;
  }

  static Future<bool> _isRegularFile(File file) async {
    return await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.file;
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

  static final Random _random = Random.secure();
}

final class _ValidatedStagingPaths {
  const _ValidatedStagingPaths({
    required this.stagingPath,
    required this.finalPath,
  });

  final String stagingPath;
  final String finalPath;
}
