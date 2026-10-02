import '../../domain/notes/note_role.dart';
import 'local_note_state.dart';
import 'local_sync_state.dart';
import 'note_sync_status.dart';
import 'pending_mutation.dart';
import 'sync_conflict.dart';
import 'sync_failure.dart';
import 'sync_snapshot.dart';

/// Applies access metadata before content revisions and pending-write filtering.
final class SyncPageProjection {
  SyncPageProjection(this.state, this.fromRemote)
    : notes = List.of(state.notes),
      outbox = List.of(state.outbox),
      conflicts = List.of(state.conflicts);
  final LocalSyncState state;
  final LocalNoteState Function(SyncNoteSnapshot, NoteSyncStatus) fromRemote;
  final List<LocalNoteState> notes;
  final List<PendingMutation> outbox;
  final List<SyncConflict> conflicts;
  int pulled = 0;
  bool changed = false;

  void apply(SyncNoteSnapshot snapshot) {
    final identity = snapshot.identityFor(state.accountUserId);
    final index = notes.indexWhere((n) => n.identity == identity);
    final old = index < 0 ? null : notes[index];
    if ((snapshot.share?.accessRevision ?? 0) <
        (old?.share?.accessRevision ?? 0)) {
      return;
    }
    final accessChanged = old != null && snapshot.share != old.share;
    final protectionChanged =
        old != null && snapshot.protection != old.protection;
    if (accessChanged || protectionChanged) {
      notes[index] = fromRemote(snapshot, NoteSyncStatus.synced);
      if (identity.ownerId != state.accountUserId) _blockStaleWork(snapshot);
      pulled++;
      changed = true;
      return;
    }
    if (_updateConflict(snapshot)) return;
    if (outbox.any(
      (m) => m.mutation.identityFor(state.accountUserId) == identity,
    )) {
      return;
    }
    if (old != null && snapshot.revision <= old.serverRevision) return;
    final incoming = fromRemote(snapshot, NoteSyncStatus.synced);
    if (index < 0) {
      notes.add(incoming);
    } else {
      notes[index] = incoming;
    }
    pulled++;
    changed = true;
  }

  bool _updateConflict(SyncNoteSnapshot snapshot) {
    final identity = snapshot.identityFor(state.accountUserId);
    final index = conflicts.indexWhere((c) => c.identity == identity);
    if (index < 0) return false;
    final old = conflicts[index];
    if (snapshot.revision > (old.remote?.revision ?? 0)) {
      conflicts[index] = SyncConflict(
        noteId: old.noteId,
        remote: snapshot,
        local: old.local,
        pending: old.pending,
        detectedAt: old.detectedAt,
      );
      changed = true;
    }
    return true;
  }

  void _blockStaleWork(SyncNoteSnapshot snapshot) {
    final identity = snapshot.identityFor(state.accountUserId);
    for (var i = 0; i < outbox.length; i++) {
      final entry = outbox[i];
      if (entry.mutation.identityFor(state.accountUserId) != identity ||
          entry.accessRevision == snapshot.share?.accessRevision &&
              snapshot.share?.isActive == true &&
              snapshot.share?.role == NoteRole.editor) {
        continue;
      }
      outbox[i] = PendingMutation(
        mutationId: entry.mutationId,
        noteId: entry.noteId,
        ownerId: entry.ownerId,
        accessRevision: entry.accessRevision,
        operation: entry.operation,
        baseRevision: entry.baseRevision,
        payload: entry.payload,
        createdAt: entry.createdAt,
        retryCount: entry.retryCount,
        lastError: SyncErrorCode.forbidden,
        blocked: true,
      );
    }
    for (var i = 0; i < conflicts.length; i++) {
      final old = conflicts[i];
      if (old.identity != identity) continue;
      final pending =
          outbox
              .where((m) => m.mutationId == old.pending.mutationId)
              .firstOrNull ??
          old.pending;
      final local = fromRemote(snapshot, NoteSyncStatus.conflict);
      conflicts[i] = SyncConflict(
        noteId: old.noteId,
        remote: snapshot,
        local: local,
        pending: pending,
        detectedAt: old.detectedAt,
      );
    }
  }
}
