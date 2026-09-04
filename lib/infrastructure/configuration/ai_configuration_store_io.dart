/// [AiConfigurationStore] implementation for iOS and Android (and any other
/// `dart:io` platform).
///
/// Persists a single schemaVersion=1 JSON envelope at
/// `<app support>/ai_configuration.json` in the application-support directory,
/// resolved with `path_provider`'s [getApplicationSupportDirectory] by default.
/// The directory resolver is injectable so unit tests run without a plugin
/// channel.
///
/// Writes are atomic: the payload is written to a same-directory temporary
/// file, flushed and closed, then renamed over the target. On failure only the
/// temporary file this write issued is cleaned up. All operations are
/// serialized per store instance. Reads never repair persisted data: corrupt
/// or unsupported files raise [AiConfigurationStoreException] unchanged.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'ai_configuration_store_contract.dart';

/// Creates a native [FileAiConfigurationStore], matching the Web stub factory.
///
/// [applicationSupportPathResolver] overrides the default
/// [getApplicationSupportDirectory] lookup (used by unit tests).
AiConfigurationStore createAiConfigurationStore({
  ApplicationSupportPathResolver? applicationSupportPathResolver,
}) {
  return FileAiConfigurationStore(
    applicationSupportPathResolver: applicationSupportPathResolver,
  );
}

/// JSON-file [AiConfigurationStore] for native platforms.
///
/// The file is private to the application and uses a versioned envelope:
///
/// ```json
/// {"schemaVersion": 1, "snapshot": { ... }}
/// ```
final class FileAiConfigurationStore implements AiConfigurationStore {
  /// [applicationSupportPathResolver] overrides the default
  /// [getApplicationSupportDirectory] lookup (used by unit tests).
  FileAiConfigurationStore({
    ApplicationSupportPathResolver? applicationSupportPathResolver,
  }) : _applicationSupportPathResolver =
           applicationSupportPathResolver ?? _defaultApplicationSupportPath;

  static const int _schemaVersion = 1;
  static const String _fileName = 'ai_configuration.json';
  static int _temporaryFileSequence = 0;

  final ApplicationSupportPathResolver _applicationSupportPathResolver;

  /// The tail is always a successful release future; operation failures are
  /// returned only to the caller of that operation and do not poison the
  /// queue for later reads or writes.
  Future<void> _operationTail = Future<void>.value();

  static Future<String> _defaultApplicationSupportPath() async {
    final Directory directory = await getApplicationSupportDirectory();
    return directory.path;
  }

  @override
  Future<AiReadinessSnapshot?> read() {
    return _enqueue<AiReadinessSnapshot?>(() async {
      final File file = await _configurationFile();
      if (!await file.exists()) {
        return null;
      }

      final String encoded;
      try {
        encoded = await file.readAsString();
      } on Object catch (error) {
        throw AiConfigurationStoreException(
          'failed to read ${file.path}',
          cause: error,
        );
      }

      return _decodeSnapshot(encoded, file.path);
    });
  }

  @override
  Future<void> save(AiReadinessSnapshot snapshot) {
    return _enqueue<void>(() async {
      final File target = await _configurationFile();

      final String encoded;
      try {
        encoded = jsonEncode(<String, Object?>{
          'schemaVersion': _schemaVersion,
          'snapshot': snapshot.toJson(),
        });
      } on Object catch (error) {
        throw AiConfigurationStoreException(
          'failed to encode the model readiness snapshot',
          cause: error,
        );
      }

      try {
        await target.parent.create(recursive: true);
      } on Object catch (error) {
        throw AiConfigurationStoreException(
          'failed to create the configuration directory',
          cause: error,
        );
      }

      final File temporary = File(_temporaryPathFor(target));
      bool temporaryIssued = false;
      try {
        await temporary.create(exclusive: true);
        temporaryIssued = true;

        final RandomAccessFile handle = await temporary.open(
          mode: FileMode.writeOnly,
        );
        try {
          await handle.writeString(encoded);
          await handle.flush();
        } finally {
          await handle.close();
        }

        // The temporary file is in the same directory, so this is one
        // filesystem rename rather than a copy followed by a delete. On the
        // supported native filesystems it atomically replaces the old file.
        await temporary.rename(target.path);
      } on Object catch (error) {
        if (temporaryIssued) {
          await _cleanIssuedTemporaryFile(temporary);
        }
        throw AiConfigurationStoreException(
          'failed to atomically write ${target.path}',
          cause: error,
        );
      }
    });
  }

  @override
  Future<void> clear() {
    return _enqueue<void>(() async {
      final File file = await _configurationFile();
      if (!await file.exists()) {
        return;
      }
      try {
        await file.delete();
      } on Object catch (error) {
        throw AiConfigurationStoreException(
          'failed to delete ${file.path}',
          cause: error,
        );
      }
    });
  }

  Future<File> _configurationFile() async {
    final String supportPath;
    try {
      supportPath = (await _applicationSupportPathResolver()).trim();
    } on Object catch (error) {
      throw AiConfigurationStoreException(
        'failed to resolve the application support directory',
        cause: error,
      );
    }
    if (supportPath.isEmpty) {
      throw const AiConfigurationStoreException(
        'the application support directory path is empty',
      );
    }
    return File(
      '${Directory(supportPath).path}${Platform.pathSeparator}$_fileName',
    );
  }

  AiReadinessSnapshot _decodeSnapshot(String encoded, String path) {
    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on Object catch (error) {
      throw AiConfigurationStoreException(
        'malformed JSON in $path',
        cause: error,
      );
    }

    final Map<String, Object?> envelope = _objectMap(
      decoded,
      'the JSON root in $path must be an object',
    );
    final Object? schemaVersion = envelope['schemaVersion'];
    if (schemaVersion is! int || schemaVersion != _schemaVersion) {
      throw AiConfigurationStoreException(
        'unsupported schemaVersion in $path: $schemaVersion',
      );
    }

    final Map<String, Object?> snapshotJson = _objectMap(
      envelope['snapshot'],
      'the snapshot field in $path must be an object',
    );
    try {
      return AiReadinessSnapshot.fromJson(snapshotJson);
    } on Object catch (error) {
      throw AiConfigurationStoreException(
        'invalid model readiness snapshot in $path',
        cause: error,
      );
    }
  }

  static Map<String, Object?> _objectMap(Object? value, String message) {
    if (value is! Map) {
      throw AiConfigurationStoreException(message);
    }

    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      final Object? key = entry.key;
      if (key is! String) {
        throw AiConfigurationStoreException(
          '$message (all keys must be strings)',
        );
      }
      result[key] = entry.value;
    }
    return result;
  }

  static String _temporaryPathFor(File target) {
    final int sequence = ++_temporaryFileSequence;
    final int timestamp = DateTime.now().microsecondsSinceEpoch;
    return '${target.path}.tmp-$pid-$timestamp-$sequence';
  }

  static Future<void> _cleanIssuedTemporaryFile(File temporary) async {
    try {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    } on Object {
      // Cleanup must never replace the original persistence failure and it
      // must not search for or delete any path other than this issued file.
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final Future<void> previous = _operationTail;
    final Completer<void> release = Completer<void>();
    _operationTail = release.future;
    return previous.then((_) async {
      try {
        return await operation();
      } finally {
        release.complete();
      }
    });
  }
}
