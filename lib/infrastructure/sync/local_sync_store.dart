/// Public entrypoint for the M2.1 account-scoped local sync store.
///
/// On platforms with `dart:io` this resolves to the `path_provider`-backed JSON
/// file implementation (`local_sync_store_io.dart`), which writes
/// `<application support>/accounts/<sha256 of the account id>/local_sync_state.json`.
/// On the Web — where `dart:io` and `path_provider` are unavailable — it
/// resolves to the IndexedDB implementation (`local_sync_store_web.dart`), which
/// uses one account-hash-specific database. Any other platform resolves to
/// `local_sync_store_stub.dart`, whose [createLocalSyncStore] returns a store
/// whose methods throw [UnsupportedError].
///
/// Every implementation binds one store instance to exactly one account:
/// [createLocalSyncStore] takes the account id, `read` returns an empty state
/// carrying that id when nothing is stored yet, and `replace` rejects state
/// that belongs to another account. Nothing here reads, imports, or migrates
/// the legacy global `notes.json` or `local-user` documents.
library;

export '../../application/sync/local_sync_store.dart' show ILocalSyncStore;

export 'local_sync_store_contract.dart';

export 'local_sync_store_stub.dart'
    if (dart.library.io) 'local_sync_store_io.dart'
    if (dart.library.js_interop) 'local_sync_store_web.dart';
