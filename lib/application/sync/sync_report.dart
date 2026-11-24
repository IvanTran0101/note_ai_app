/// Outcome of one sync run.
library;

import 'sync_cursor.dart';

/// Immutable summary of one completed sync run.
///
/// The counts are non-negative and independent: one run can apply local
/// mutations, pull remote snapshots, and record conflicts. [cursor] is the
/// opaque remote position the caller should persist after the run; it is null
/// when the run did not produce a new cursor.
final class SyncReport {
  /// Creates a validated report.
  SyncReport({
    this.applied = 0,
    this.pulled = 0,
    this.conflicts = 0,
    this.cursor,
  }) {
    _requireNonNegative(applied, 'applied');
    _requireNonNegative(pulled, 'pulled');
    _requireNonNegative(conflicts, 'conflicts');
  }

  /// How many queued local mutations the server applied.
  final int applied;

  /// How many remote snapshots were merged into the local store.
  final int pulled;

  /// How many conflicts this run recorded.
  final int conflicts;

  /// The opaque cursor to persist after the run, or null when unchanged.
  final SyncCursor? cursor;

  /// True when the run changed nothing and recorded no conflict.
  bool get isNoop => applied == 0 && pulled == 0 && conflicts == 0;

  @override
  bool operator ==(Object other) {
    return other is SyncReport &&
        other.applied == applied &&
        other.pulled == pulled &&
        other.conflicts == conflicts &&
        other.cursor == cursor;
  }

  @override
  int get hashCode => Object.hash(applied, pulled, conflicts, cursor);

  @override
  String toString() {
    return 'SyncReport(applied: $applied, pulled: $pulled, '
        'conflicts: $conflicts, '
        'cursor: ${cursor == null ? 'none' : 'present'})';
  }
}

void _requireNonNegative(int value, String fieldName) {
  if (value < 0) {
    throw ArgumentError.value(value, fieldName, 'must not be negative');
  }
}
