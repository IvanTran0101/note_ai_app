/// [ILocalSyncStore] implementation for the Web.
///
/// Stores one account's whole local sync state in that account's own IndexedDB
/// database: one object store (`local_sync_state`) holds one record (key
/// `state`) whose value is the JSON-encoded schemaVersion 2 envelope. The database name
/// is the SHA-256 digest of the account id, never the raw id, and the same
/// digest names the native account directory, so an account identifier never
/// appears in a browser-visible database name.
///
/// [IndexedDbLocalSyncStore.replace] writes the envelope and then awaits
/// transaction completion, so notes, outbox, cursor, and conflicts commit
/// together or not at all: a reader can never observe a half-written state.
/// [IndexedDbLocalSyncStore.update] reads, transforms, and writes that envelope
/// in one read-write transaction, preventing local edits and sync checkpoints
/// from replacing one another with stale snapshots.
/// [IndexedDbLocalSyncStore.read] returns an empty state when the account has
/// no record yet and strictly decodes an existing one, raising
/// [LocalSyncStoreException] when it is malformed or belongs to another
/// account. Reads never repair persisted data.
///
/// Only this library imports `package:indexed_db`; the shared codec, contract,
/// and account namespace stay platform-neutral. The binding uses `package:web`
/// underneath, so this adapter compiles and runs for JavaScript and for Wasm:
/// every value that crosses into IndexedDB is converted explicitly, and the
/// stored string is accepted back as a Dart or a JavaScript string.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:indexed_db/indexed_db.dart';

import '../../application/sync/local_sync_state.dart';
import '../../application/sync/local_sync_store.dart';
import 'local_sync_state_codec.dart';
import 'local_sync_store_account_namespace.dart';
import 'local_sync_store_contract.dart';

/// Creates a Web [IndexedDbLocalSyncStore], matching the native factory.
///
/// [applicationSupportPathResolver] exists only for signature parity with the
/// native factory and the stub: the Web stores state in IndexedDB, not in a
/// file, so the resolver is accepted and ignored.
ILocalSyncStore createLocalSyncStore({
  required String accountUserId,
  LocalSyncApplicationSupportPathResolver? applicationSupportPathResolver,
}) {
  return IndexedDbLocalSyncStore(accountUserId: accountUserId);
}

/// IndexedDB [ILocalSyncStore] for the Web.
final class IndexedDbLocalSyncStore implements ILocalSyncStore {
  /// Binds the store to [accountUserId]'s own database.
  IndexedDbLocalSyncStore({required String accountUserId})
    : _namespace = LocalSyncAccountNamespace(accountUserId);

  /// The only object store in an account database.
  static const String _objectStoreName = 'local_sync_state';

  /// The only record key in that object store: the whole envelope.
  static const String _recordKey = 'state';

  /// IndexedDB schema version of the account database.
  ///
  /// It is fixed, so the store never requests a version upgrade of an open
  /// database and an open request cannot be blocked by another tab. The M2
  /// envelope version is tracked by `LocalSyncStateCodec.schemaVersion` inside
  /// the record instead.
  static const int _databaseVersion = 1;

  final LocalSyncAccountNamespace _namespace;

  Future<Database>? _openDatabaseFuture;

  @override
  Future<LocalSyncState> read() async {
    final Database database = await _database();

    final Transaction transaction;
    final Object? record;
    try {
      transaction = _transaction(database, 'readonly');
      record = await transaction
          .objectStore(_objectStoreName)
          .getObject(_recordKey.toJS);
      await transaction.completed;
    } on Object {
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.unreadable,
        'the local sync state could not be read',
      );
    }

    if (record == null) {
      return LocalSyncState(accountUserId: _namespace.accountUserId);
    }
    return _decode(record);
  }

  @override
  Future<void> replace(LocalSyncState state) async {
    _namespace.requireOwned(state);

    final String encoded;
    try {
      encoded = jsonEncode(LocalSyncStateCodec.encode(state));
    } on Object {
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.unwritable,
        'the local sync state could not be encoded',
      );
    }

    final Database database = await _database();
    try {
      final Transaction transaction = _transaction(database, 'readwrite');
      await transaction
          .objectStore(_objectStoreName)
          .put(encoded.toJS, _recordKey.toJS);

      // Transaction completion, not request success, is what makes the whole
      // envelope durable: notes, outbox, cursor, and conflicts commit in one
      // transaction or not at all.
      await transaction.completed;
    } on Object {
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.unwritable,
        'the local sync state could not be replaced',
      );
    }
  }

  @override
  Future<LocalSyncState> update(
    LocalSyncState Function(LocalSyncState current) transform,
  ) async {
    final Database database = await _database();
    final Transaction transaction;
    final ObjectStore store;
    try {
      transaction = _transaction(database, 'readwrite');
      store = transaction.objectStore(_objectStoreName);
    } on Object {
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.unwritable,
        'the local sync state transaction could not be opened',
      );
    }

    final Object? record;
    try {
      record = await store.getObject(_recordKey.toJS);
    } on Object {
      _abort(transaction);
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.unreadable,
        'the local sync state could not be read',
      );
    }

    final LocalSyncState current;
    try {
      current = record == null
          ? LocalSyncState(accountUserId: _namespace.accountUserId)
          : _decode(record);
    } on Object catch (error, stackTrace) {
      _abort(transaction);
      Error.throwWithStackTrace(error, stackTrace);
    }

    final LocalSyncState next;
    try {
      next = transform(current);
      _namespace.requireOwned(next);
    } on Object catch (error, stackTrace) {
      _abort(transaction);
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (next == current) {
      await transaction.completed;
      return current;
    }

    final String encoded;
    try {
      encoded = jsonEncode(LocalSyncStateCodec.encode(next));
    } on Object {
      _abort(transaction);
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.unwritable,
        'the local sync state could not be encoded',
      );
    }

    try {
      await store.put(encoded.toJS, _recordKey.toJS);
      await transaction.completed;
    } on Object {
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.unwritable,
        'the local sync state could not be replaced',
      );
    }
    return next;
  }

  /// Opens a transaction over the one envelope object store.
  ///
  /// Store names are passed as a converted list instead of through the
  /// package's string convenience method, which forwards a Dart string through
  /// a `dynamic` parameter: the Wasm backend cannot cast that to a JavaScript
  /// value, while `transactionList` converts the names itself. The same code
  /// therefore runs on the JavaScript and the Wasm backends.
  Transaction _transaction(Database database, String mode) {
    return database.transactionList(<String>[_objectStoreName], mode);
  }

  void _abort(Transaction transaction) {
    try {
      transaction.abort();
    } on Object {
      // An already-finished transaction needs no further cleanup.
    }
    unawaited(transaction.completed.then<void>((_) {}, onError: (Object _) {}));
  }

  /// Decodes a stored record without ever letting a value escape.
  ///
  /// A record that is not the exact M2 envelope, a database name, and an
  /// account id all stay out of the raised exception.
  LocalSyncState _decode(Object record) {
    final String? encoded = _jsonText(record);
    if (encoded == null) {
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.malformed,
        'the stored local sync state is not JSON text',
      );
    }

    final Object? data;
    final LocalSyncState state;
    try {
      data = jsonDecode(encoded);
      state = LocalSyncStateCodec.decode(data);
    } on Object {
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.malformed,
        'the stored local sync state does not match the M2 schema',
      );
    }

    _namespace.requireOwned(state);
    return state;
  }

  /// The JSON text of [record], or null when it is not text at all.
  ///
  /// IndexedDB returns the stored value as a Dart string on the JavaScript
  /// backend and as a JavaScript string on the Wasm backend, so both are
  /// accepted here and every other value stays a strict decoding failure.
  static String? _jsonText(Object record) {
    if (record is String) {
      return record;
    }
    if (record.isA<JSString>()) {
      return (record as JSString).toDart;
    }
    return null;
  }

  Future<Database> _database() {
    final Future<Database>? cached = _openDatabaseFuture;
    if (cached != null) {
      return cached;
    }

    final Future<Database> opening = _open();
    _openDatabaseFuture = opening;
    opening.then<void>(
      (_) {},
      onError: (Object _) {
        // A failed open is not cached, so the next operation retries instead of
        // failing forever.
        if (identical(_openDatabaseFuture, opening)) {
          _openDatabaseFuture = null;
        }
      },
    );
    return opening;
  }

  Future<Database> _open() async {
    try {
      final Database database = await IdbFactory().open(
        _namespace.webDatabaseName,
        version: _databaseVersion,
        onUpgradeNeeded: (VersionChangeEvent event) {
          final Database upgrading = event.target.database;
          final List<String> stores =
              upgrading.objectStoreNames ?? const <String>[];
          if (!stores.contains(_objectStoreName)) {
            upgrading.createObjectStore(_objectStoreName);
          }
        },
      );

      // Another context opening a newer database version closes this
      // connection, so the cached handle is dropped and reopened on demand.
      database.onVersionChange.listen((VersionChangeEvent event) {
        database.close();
        _openDatabaseFuture = null;
      });
      return database;
    } on Object {
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.unavailable,
        'the local sync state database could not be opened',
      );
    }
  }
}
