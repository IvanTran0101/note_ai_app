import 'dart:js_interop';
import 'dart:async';

import 'package:indexed_db/indexed_db.dart';

import '../../application/sync/local_sync_store.dart';
import '../security/encoded_account_store.dart';
import '../security/encrypted_sync_store.dart';
import '../security/paged_account_store.dart';
import 'local_sync_store_account_namespace.dart';
import 'local_sync_store_contract.dart';

part 'local_sync_pages_web.dart';

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
final class _WebAccountStore implements EncodedAccountStore, PagedAccountStore {
  _WebAccountStore(String accountId)
    : namespace = LocalSyncAccountNamespace(accountId);
  final LocalSyncAccountNamespace namespace;
  static const _store = 'local_sync_state';
  static const _record = 'state';
  static const _meta = 'note_page_meta_v1';
  static const _pages = 'note_page_records_v1';
  @override
  bool pageMode = false;
  Future<Database>? _opening;

  Future<Database> _database() => _opening ??= _open();
  Future<Database> _open() async {
    try {
      final database = await IdbFactory().open(
        namespace.webDatabaseName,
        version: 3,
        onUpgradeNeeded: (VersionChangeEvent event) {
          final db = event.target.database;
          if (!(db.objectStoreNames ?? []).contains(_store)) {
            db.createObjectStore(_store);
          }
          for (final name in [_meta, _pages]) {
            if (!(db.objectStoreNames ?? []).contains(name)) {
              db.createObjectStore(name);
            }
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
      final tx = (await _database()).transactionList([
        _store,
        _meta,
      ], 'readonly');
      final record = await tx.objectStore(_store).getObject(_record.toJS);
      pageMode =
          _text(await tx.objectStore(_meta).getObject('head'.toJS)) != null;
      await tx.completed;
      if (record == null && pageMode) throw const CorruptPageRead();
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
    return _commitPages(expected, encrypted, null);
  }

  @override
  Future<PagedEncodedView?> openPagedView() => _openPages();
  @override
  Future<String> readPagedRecord(String generation, String key) =>
      _readPage(generation, key);
  @override
  Future<void> requirePagedGeneration(String generation) =>
      _requirePages(generation);
  @override
  Future<bool> compareAndSetPaged(
    String? expected,
    String encrypted,
    PagedEncodedCommit pages,
  ) => _commitPages(expected, encrypted, pages);

  @override
  Future<void> cleanLegacyStaging(
    String accountId,
    Future<String> Function(String) sealLegacy,
  ) async {
    /* one atomic record, no staging copies */
  }
}
