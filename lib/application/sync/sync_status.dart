/// Observable sync state of the local-first client.
library;

import 'sync_failure.dart';

/// High-level sync standing of one account on this device.
enum SyncStatus {
  /// Nothing is scheduled; the last run finished or none started.
  idle,

  /// The device is offline, so sync is waiting for connectivity.
  offline,

  /// A sync run is in progress.
  syncing,

  /// The last sync run ended in a failure that is not being retried.
  failed,
}

/// Immutable observation of the current [SyncStatus].
///
/// [failure] is present exactly when [status] is [SyncStatus.failed]: a failure
/// cannot be attached to any other status, and the failed status cannot omit
/// it. The snapshot is primitive-first and safe to publish to any observer.
final class SyncStatusSnapshot {
  /// Creates a snapshot, validating the status/failure pairing.
  SyncStatusSnapshot({required this.status, this.failure}) {
    if (failure != null && status != SyncStatus.failed) {
      throw ArgumentError.value(
        status,
        'status',
        'a failure may only be attached to the failed status',
      );
    }
    if (status == SyncStatus.failed && failure == null) {
      throw ArgumentError.value(
        status,
        'status',
        'the failed status requires a failure',
      );
    }
  }

  /// A snapshot for [SyncStatus.idle].
  const SyncStatusSnapshot.idle() : status = SyncStatus.idle, failure = null;

  /// A snapshot for [SyncStatus.offline].
  const SyncStatusSnapshot.offline()
    : status = SyncStatus.offline,
      failure = null;

  /// A snapshot for [SyncStatus.syncing].
  const SyncStatusSnapshot.syncing()
    : status = SyncStatus.syncing,
      failure = null;

  /// A snapshot for [SyncStatus.failed], carrying the ending [failure].
  SyncStatusSnapshot.failed(SyncFailure failure)
    : this(status: SyncStatus.failed, failure: failure);

  /// The current sync status.
  final SyncStatus status;

  /// The failure that ended the last run, present only for
  /// [SyncStatus.failed].
  final SyncFailure? failure;

  /// True when a sync run is currently in progress.
  bool get isSyncing => status == SyncStatus.syncing;

  /// True when the last run ended in a failure.
  bool get isFailed => status == SyncStatus.failed;

  @override
  bool operator ==(Object other) {
    return other is SyncStatusSnapshot &&
        other.status == status &&
        other.failure == failure;
  }

  @override
  int get hashCode => Object.hash(status, failure);

  @override
  String toString() {
    return 'SyncStatusSnapshot(status: ${status.name}, '
        'failure: ${failure?.code.name ?? 'none'})';
  }
}
