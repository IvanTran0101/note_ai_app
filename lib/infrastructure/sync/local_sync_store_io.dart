/// [ILocalSyncStore] implementation for `dart:io` platforms.
///
/// Persists one account's whole local sync state as a schemaVersion 2 JSON
/// envelope at
/// `<app support>/accounts/<sha256 of the account id>/local_sync_state.json`,
/// resolved with `path_provider`'s [getApplicationSupportDirectory] by default.
/// The directory resolver is injectable so unit tests run without a plugin
/// channel.
///
/// The account namespace is the SHA-256 digest of the account id, never the raw
/// id, so an account identifier does not appear in any file or directory name.
/// Each
/// store instance is bound to exactly one account: [FileLocalSyncStore.read]
/// returns an empty state for that account when nothing is stored yet, and
/// [FileLocalSyncStore.replace] rejects state of another account.
///
/// Writes are atomic: the encoded envelope is written to a same-directory
/// temporary file, flushed and closed, then renamed over the target. On failure
/// only the temporary file this write issued is cleaned up, so a failed
/// replacement leaves the previously stored state in place. All operations are
/// serialized per store instance. Reads never repair persisted data: a
/// malformed document, or one that carries another account, raises
/// [LocalSyncStoreException] and is left exactly as it was found.
///
/// The legacy global `notes.json` and `local-user` documents are not read,
/// imported, or migrated here.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../application/sync/local_sync_state.dart';
import '../../application/sync/local_sync_store.dart';
import 'local_sync_state_codec.dart';
import 'local_sync_store_account_namespace.dart';
import 'local_sync_store_contract.dart';

/// Creates a native [FileLocalSyncStore], matching the Web and stub factories.
///
/// [applicationSupportPathResolver] overrides the default
/// [getApplicationSupportDirectory] lookup (used by unit tests). The Web and
/// stub factories accept the same parameter and ignore it.
ILocalSyncStore createLocalSyncStore({
  required String accountUserId,
  LocalSyncApplicationSupportPathResolver? applicationSupportPathResolver,
}) {
  return FileLocalSyncStore(
    accountUserId: accountUserId,
    applicationSupportPathResolver: applicationSupportPathResolver,
  );
}

/// JSON-file [ILocalSyncStore] for native platforms.
///
/// The file is private to the application and holds exactly one envelope:
///
/// ```json
/// {"schemaVersion": 2, "accountUserId": "...", "notes": [], ...}
/// ```
final class FileLocalSyncStore implements ILocalSyncStore {
  /// Binds the store to [accountUserId].
  ///
  /// [applicationSupportPathResolver] overrides the default
  /// [getApplicationSupportDirectory] lookup (used by unit tests).
  FileLocalSyncStore({
    required String accountUserId,
    LocalSyncApplicationSupportPathResolver? applicationSupportPathResolver,
  }) : _namespace = LocalSyncAccountNamespace(accountUserId),
       _applicationSupportPathResolver =
           applicationSupportPathResolver ?? _defaultApplicationSupportPath;

  /// File name of the whole-state document inside the account namespace.
  static const String _fileName = 'local_sync_state.json';
  static int _temporaryFileSequence = 0;

  final LocalSyncAccountNamespace _namespace;
  final LocalSyncApplicationSupportPathResolver _applicationSupportPathResolver;

  /// The tail is always a successful release future; operation failures are
  /// returned only to the caller of that operation and do not poison the queue
  /// for later reads or writes.
  Future<void> _operationTail = Future<void>.value();

  static Future<String> _defaultApplicationSupportPath() async {
    final Directory directory = await getApplicationSupportDirectory();
    return directory.path;
  }

  @override
  Future<LocalSyncState> read() {
    return _enqueue<LocalSyncState>(() async {
      final File file = await _stateFile();
      if (!await file.exists()) {
        return _emptyState();
      }

      final String encoded;
      try {
        encoded = await file.readAsString();
      } on Object {
        throw const LocalSyncStoreException(
          LocalSyncStoreFailure.unreadable,
          'the local sync state could not be read',
        );
      }

      return _decode(encoded);
    });
  }

  @override
  Future<void> replace(LocalSyncState state) {
    return _enqueue<void>(() async {
      _namespace.requireOwned(state);

      final File target = await _stateFile();

      final String encoded;
      try {
        encoded = jsonEncode(LocalSyncStateCodec.encode(state));
      } on Object {
        throw const LocalSyncStoreException(
          LocalSyncStoreFailure.unwritable,
          'the local sync state could not be encoded',
        );
      }

      try {
        await target.parent.create(recursive: true);
      } on Object {
        throw const LocalSyncStoreException(
          LocalSyncStoreFailure.unwritable,
          'the local sync state namespace directory could not be created',
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
        // supported native filesystems it atomically replaces the old file, so
        // a reader sees either the previous complete state or the new one.
        await temporary.rename(target.path);
      } on Object {
        if (temporaryIssued) {
          await _cleanIssuedTemporaryFile(temporary);
        }
        throw const LocalSyncStoreException(
          LocalSyncStoreFailure.unwritable,
          'the local sync state could not be replaced',
        );
      }
    });
  }

  LocalSyncState _emptyState() {
    return LocalSyncState(accountUserId: _namespace.accountUserId);
  }

  /// Decodes a stored document without ever letting a value escape.
  ///
  /// Every failure becomes one of two typed failures with a fixed message: a
  /// codec path, a note title, a cursor value, an account id, and this file's
  /// path all stay out of the exception.
  LocalSyncState _decode(String encoded) {
    final Object? document;
    try {
      document = jsonDecode(encoded);
    } on Object {
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.malformed,
        'the stored local sync state is not valid JSON',
      );
    }

    final LocalSyncState state;
    try {
      state = LocalSyncStateCodec.decode(document);
    } on Object {
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.malformed,
        'the stored local sync state does not match the M2 schema',
      );
    }

    _namespace.requireOwned(state);
    return state;
  }

  Future<File> _stateFile() async {
    final String supportPath;
    try {
      supportPath = (await _applicationSupportPathResolver()).trim();
    } on Object {
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.unavailable,
        'the application support directory could not be resolved',
      );
    }
    if (supportPath.isEmpty) {
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.unavailable,
        'the application support directory path is empty',
      );
    }

    final String separator = Platform.pathSeparator;
    return File(
      '${Directory(supportPath).path}$separator'
      '${LocalSyncAccountNamespace.accountsDirectoryName}$separator'
      '${_namespace.hash}$separator$_fileName',
    );
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
      // Cleanup must never replace the original persistence failure, and it
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
