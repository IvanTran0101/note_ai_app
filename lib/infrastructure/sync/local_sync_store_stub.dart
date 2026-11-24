/// Safe unavailable implementation of [ILocalSyncStore].
///
/// Platforms that are neither `dart:io` nor JavaScript/Wasm — and therefore
/// have no application-support directory and no IndexedDB — resolve to this
/// library. [createLocalSyncStore] returns an [UnsupportedLocalSyncStore] so
/// such a build compiles and starts; every [read] and [replace] call throws
/// [UnsupportedError]. There is deliberately NO memory-only fallback: a store
/// that silently forgets local note state would be worse than a clear failure.
library;

import '../../application/sync/local_sync_state.dart';
import '../../application/sync/local_sync_store.dart';
import 'local_sync_store_contract.dart';

/// A store that is never usable: this platform has no durable local sync
/// backing store. The factory signature matches the native and Web
/// implementations so the conditional facade swaps them without a call-site
/// difference.
final class UnsupportedLocalSyncStore implements ILocalSyncStore {
  /// Constructor signature matches the native and Web implementations; the
  /// account id and the resolver are accepted and ignored because no state is
  /// ever read or written.
  UnsupportedLocalSyncStore({
    required String accountUserId,
    LocalSyncApplicationSupportPathResolver? applicationSupportPathResolver,
  });

  @override
  Future<LocalSyncState> read() {
    throw UnsupportedError(
      'The local sync store is not available on this platform. Local sync '
      'state is not persisted here.',
    );
  }

  @override
  Future<LocalSyncState> update(
    LocalSyncState Function(LocalSyncState current) transform,
  ) {
    throw UnsupportedError(
      'The local sync store is not available on this platform. Local sync '
      'state is not persisted here.',
    );
  }

  @override
  Future<void> replace(LocalSyncState state) {
    throw UnsupportedError(
      'The local sync store is not available on this platform. Local sync '
      'state is not persisted here.',
    );
  }
}

/// Returns an unavailable [UnsupportedLocalSyncStore] on platforms without a
/// durable local sync backing store. The signature matches the native and Web
/// factories.
ILocalSyncStore createLocalSyncStore({
  required String accountUserId,
  LocalSyncApplicationSupportPathResolver? applicationSupportPathResolver,
}) {
  return UnsupportedLocalSyncStore(
    accountUserId: accountUserId,
    applicationSupportPathResolver: applicationSupportPathResolver,
  );
}
