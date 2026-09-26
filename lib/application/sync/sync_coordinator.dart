/// Future-facing Application port for running synchronization.
library;

import 'dart:async';

import 'sync_report.dart';
import 'sync_status.dart';

/// The Application boundary that runs one account's synchronization.
///
/// This is a contract only: M2.0 freezes the port so storage, outbox, and
/// remote adapters can be built against it, and no implementation ships yet.
/// A future implementation owns trigger policy, retry/backoff, and conflict
/// resolution; callers observe [status] and persist the cursor carried by the
/// returned report through their local store.
abstract interface class ISyncCoordinator {
  /// The most recent status observation, available synchronously.
  SyncStatusSnapshot get status;

  /// Status observations, newest last.
  ///
  /// A listener receives every later change; the current value is always
  /// available from [status] without waiting for an event.
  Stream<SyncStatusSnapshot> get statusChanges;

  /// Runs one synchronization pass to completion.
  ///
  /// Returns the report of what that pass changed. A network-unavailable
  /// failure publishes [SyncStatus.offline]; other failures publish
  /// [SyncStatus.failed]. All failures are also reported through the returned
  /// future.
  Future<SyncReport> syncNow();
}
