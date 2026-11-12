import 'dart:js_interop';

import 'package:indexed_db/indexed_db.dart';

import '../../application/sync/local_sync_store.dart';
import '../security/encoded_account_store.dart';
import '../security/encrypted_sync_store.dart';
import 'local_sync_store_account_namespace.dart';
import 'local_sync_store_contract.dart';

ILocalSyncStore createLocalSyncStore({
  required String accountUserId,
  LocalSyncApplicationSupportPathResolver? applicationSupportPathResolver,
}) => IndexedDbLocalSyncStore(accountUserId: accountUserId);

final class IndexedDbLocalSyncStore extends EncryptedSyncStore {
  IndexedDbLocalSyncStore({required String accountUserId})
    : super(accountUserId, _WebAccountStore(accountUserId));
}

/// Crypto awaits outside transactions. CAS commits the single encrypted record
/// in one transaction so a different tab cannot overwrite a stale snapshot.
final class _WebAccountStore implements EncodedAccountStore {
  _WebAccountStore(String accountId)
    : namespace = LocalSyncAccountNamespace(accountId);
  final LocalSyncAccountNamespace namespace;
  static const _store = 'local_sync_state';
  static const _record = 'state';
  Future<Database>? _opening;

  Future<Database> _database() => _opening ??= _open();
  Future<Database> _open() async {
    try {
      final database = await IdbFactory().open(
        namespace.webDatabaseName,
        version: 2,
        onUpgradeNeeded: (VersionChangeEvent event) {
          final db = event.target.database;
          if (!(db.objectStoreNames ?? []).contains(_store)) {
            db.createObjectStore(_store);
          }
        },
      );
      database.onVersionChange.listen((_) {
        database.close();
        _opening = null;
      });
      return database;
    } on Object {
      _opening = null;
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.unavailable,
        'local database unavailable',
      );
    }
  }

  static String? _text(Object? record) {
    if (record == null) return null;
    final String result;
    if (record is String) {
      result = record;
    } else if (record.isA<JSString>()) {
      result = (record as JSString).toDart;
    } else {
      throw const FormatException();
    }
    if (result.length > 32 * 1024 * 1024) throw const FormatException();
    return result;
  }

  @override
  Future<String?> readEncoded() async {
    try {
      final tx = (await _database()).transactionList([_store], 'readonly');
      final record = await tx.objectStore(_store).getObject(_record.toJS);
      await tx.completed;
      return _text(record);
    } on Object {
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.unreadable,
        'local state cannot be read',
      );
    }
  }

  @override
  Future<bool> compareAndSet(String? expected, String encrypted) async {
    try {
      final tx = (await _database()).transactionList([_store], 'readwrite');
      final store = tx.objectStore(_store);
      final current = _text(await store.getObject(_record.toJS));
      if (current != expected) {
        await tx.completed;
        return false;
      }
      await store.put(encrypted.toJS, _record.toJS);
      await tx.completed;
      return true;
    } on Object {
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.unwritable,
        'encrypted state cannot be committed',
      );
    }
  }

  @override
  Future<void> cleanLegacyStaging(
    String accountId,
    Future<String> Function(String) sealLegacy,
  ) async {
    /* one atomic record, no staging copies */
  }
}
