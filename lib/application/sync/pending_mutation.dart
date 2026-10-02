/// One queued local change waiting to be pushed to the remote note API.
library;

import 'sync_failure.dart';
import 'sync_mutation.dart';

/// Immutable outbox entry for one note mutation.
///
/// The wire mutation is built through [SyncMutation], so the frozen M1 rules
/// apply unchanged: `create` and `update` require a payload, `delete` may omit
/// it, ids must not be blank, and the base revision must not be negative.
///
/// [mutationId] is stable for the whole life of the entry, including every
/// retry: the server's idempotency guarantee depends on resending the same id.
/// [retryCount], [lastError], and [blocked] are the local attempt bookkeeping.
final class PendingMutation {
  /// Creates a validated outbox entry.
  PendingMutation({
    required String mutationId,
    required String noteId,
    required SyncMutationOperation operation,
    required int baseRevision,
    SyncNotePayload? payload,
    String? ownerId,
    int? accessRevision,
    required this.createdAt,
    int retryCount = 0,
    this.lastError,
    this.blocked = false,
  }) : mutation = SyncMutation(
         mutationId: mutationId,
         noteId: noteId,
         operation: operation,
         baseRevision: baseRevision,
         payload: payload,
         ownerId: ownerId,
         accessRevision: accessRevision,
       ),
       retryCount = _requireNonNegative(retryCount, 'retryCount');

  /// The wire mutation this entry pushes, carrying the stable id.
  final SyncMutation mutation;

  /// When the local change was queued.
  final DateTime createdAt;

  /// How many push attempts were already made; never negative.
  final int retryCount;

  /// The error code of the last failed attempt, or null when none failed yet.
  final SyncErrorCode? lastError;

  /// True when automatic retry stopped and the entry needs a caller decision.
  final bool blocked;

  /// Stable identity of this entry, reused for every retry.
  String get mutationId => mutation.mutationId;

  /// The note this entry changes.
  String get noteId => mutation.noteId;
  String? get ownerId => mutation.ownerId;
  int? get accessRevision => mutation.accessRevision;
  String keyFor(String actorId) => mutation.identityFor(actorId).key;

  /// The operation to push.
  SyncMutationOperation get operation => mutation.operation;

  /// The revision the local change was based on.
  int get baseRevision => mutation.baseRevision;

  /// The note fields to push, present for `create` and `update`.
  SyncNotePayload? get payload => mutation.payload;

  /// The wire mutation to push, preserving the stable [mutationId].
  SyncMutation toMutation() => mutation;

  @override
  bool operator ==(Object other) {
    return other is PendingMutation &&
        other.mutation == mutation &&
        other.createdAt == createdAt &&
        other.retryCount == retryCount &&
        other.lastError == lastError &&
        other.blocked == blocked;
  }

  @override
  int get hashCode =>
      Object.hash(mutation, createdAt, retryCount, lastError, blocked);

  @override
  String toString() {
    return 'PendingMutation(mutationId: $mutationId, noteId: $noteId, '
        'operation: ${operation.name}, baseRevision: $baseRevision, '
        'retryCount: $retryCount, lastError: ${lastError?.name ?? 'none'}, '
        'blocked: $blocked)';
  }
}

int _requireNonNegative(int value, String fieldName) {
  if (value < 0) {
    throw ArgumentError.value(value, fieldName, 'must not be negative');
  }
  return value;
}
