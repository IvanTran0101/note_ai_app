/// Application port for the local sync store.
library;

import 'local_sync_state.dart';

/// The local persistence boundary for one account's sync state.
///
/// The store owns durability only; it holds no sync policy, no conflict
/// resolution, and no remote knowledge. The future Infrastructure adapter
/// (IndexedDB or any other backend) implements this port with provider-neutral
/// types, so Application never sees a storage SDK.
abstract interface class ILocalSyncStore {
  /// Reads the whole stored state for the account.
  ///
  /// Returns an empty state when nothing has been persisted yet; it never
  /// returns null and never returns a partial state.
  Future<LocalSyncState> read();

  /// Atomically replaces the whole stored state.
  ///
  /// The replacement is all-or-nothing: a reader observes either the previous
  /// complete state or [state], never a mix of the two, even when the process
  /// stops mid-write. [state] is already validated, so the store only persists
  /// it.
  Future<void> replace(LocalSyncState state);
}
