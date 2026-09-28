/// One unresolved revision conflict between a local note and the server.
library;

import 'local_note_state.dart';
import 'pending_mutation.dart';
import 'sync_snapshot.dart';

/// Immutable record of one mutation the server rejected with a conflict.
///
/// [remote] is the server snapshot that won the revision race. It is null when
/// the server reported a conflict without returning the remote note; a server
/// tombstone is a non-null snapshot whose `deletedAt` is set, so a conflicting
/// remote deletion is distinguishable from a missing remote note.
///
/// [local] and [pending] are the local side that lost. They must describe the
/// same [noteId], so a conflict cannot be assembled from mismatched records.
final class SyncConflict {
  /// Creates a validated conflict record.
  SyncConflict({
    required String noteId,
    this.remote,
    required this.local,
    required this.pending,
    required this.detectedAt,
  }) : noteId = _requireNonBlank(noteId, 'noteId') {
    if (local.id != this.noteId) {
      throw ArgumentError.value(
        local.id,
        'local',
        'must describe note ${this.noteId}',
      );
    }
    if (pending.noteId != this.noteId) {
      throw ArgumentError.value(
        pending.noteId,
        'pending',
        'must change note ${this.noteId}',
      );
    }
    final SyncNoteSnapshot? remoteNote = remote;
    if (remoteNote != null && remoteNote.id != this.noteId) {
      throw ArgumentError.value(
        remoteNote.id,
        'remote',
        'must describe note ${this.noteId}',
      );
    }
  }

  /// The note both sides disagree about.
  final String noteId;

  /// The server snapshot that won, or null when it was not returned.
  final SyncNoteSnapshot? remote;

  /// The local state that lost the race.
  final LocalNoteState local;

  /// The rejected local mutation, kept for resolution and retry.
  final PendingMutation pending;

  /// When the conflict was recorded locally.
  final DateTime detectedAt;

  /// True when the winning remote side is a tombstone.
  bool get isRemoteDeleted => remote?.isDeleted ?? false;

  @override
  bool operator ==(Object other) {
    return other is SyncConflict &&
        other.noteId == noteId &&
        other.remote == remote &&
        other.local == local &&
        other.pending == pending &&
        other.detectedAt == detectedAt;
  }

  @override
  int get hashCode => Object.hash(noteId, remote, local, pending, detectedAt);

  @override
  String toString() {
    return 'SyncConflict(noteId: $noteId, '
        'remote: ${remote == null ? 'absent' : (isRemoteDeleted ? 'tombstone' : 'live')}, '
        'localRevision: ${local.serverRevision}, '
        'mutationId: ${pending.mutationId})';
  }
}

String _requireNonBlank(String value, String fieldName) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, fieldName, 'must not be blank');
  }
  return value;
}
