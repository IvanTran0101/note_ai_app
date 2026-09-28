import 'local_note_state.dart';
import 'local_sync_state.dart';
import 'local_sync_store.dart';
import 'note_sync_status.dart';
import 'pending_mutation.dart';
import 'sync_conflict.dart';
import 'sync_cursor.dart';
import 'sync_failure.dart';
import 'sync_result.dart';
import 'sync_snapshot.dart';

/// Applies remote outcomes to fresh local state inside store transactions.
final class SyncStateReconciliation {
  SyncStateReconciliation({
    required this.accountUserId,
    required this.localStore,
    required this.clock,
  });

  final String accountUserId;
  final ILocalSyncStore localStore;
  final DateTime Function() clock;

  Future<LocalSyncState> read() async {
    final LocalSyncState state = await localStore.read();
    if (state.accountUserId != accountUserId) {
      throw const SyncFailure(code: SyncErrorCode.forbidden);
    }
    return state;
  }

  Future<LocalSyncState> update(
    LocalSyncState Function(LocalSyncState current) transform,
  ) => localStore.update((current) {
    if (current.accountUserId != accountUserId) {
      throw const SyncFailure(code: SyncErrorCode.forbidden);
    }
    return transform(current);
  });

  Future<void> recordPushFailure(String mutationId, SyncFailure failure) async {
    await update((current) {
      final int index = current.outbox.indexWhere(
        (PendingMutation item) => item.mutationId == mutationId,
      );
      if (index < 0) return current;
      final PendingMutation entry = current.outbox[index];
      final List<PendingMutation> outbox =
          List<PendingMutation>.of(current.outbox)
            ..[index] = copyEntry(
              entry,
              lastError: failure.code,
              blocked: failure.code == SyncErrorCode.invalidMutation,
            );
      final List<LocalNoteState> notes =
          failure.code == SyncErrorCode.invalidMutation
          ? current.notes
                .map(
                  (LocalNoteState note) => note.id == entry.noteId
                      ? withStatus(note, NoteSyncStatus.failed)
                      : note,
                )
                .toList()
          : current.notes;
      return copyState(current, outbox: outbox, notes: notes);
    });
  }

  Future<bool> recordConflict(
    PendingMutation requested,
    SyncMutationResult result,
  ) async {
    final DateTime detectedAt = clock();
    final LocalSyncState updated = await update((current) {
      final int entryIndex = current.outbox.indexWhere(
        (PendingMutation item) => item.mutationId == requested.mutationId,
      );
      if (entryIndex < 0) return current;
      final int noteIndex = current.notes.indexWhere(
        (LocalNoteState note) => note.id == requested.noteId,
      );
      final SyncNoteSnapshot? remote = result.conflictRemote;
      if (noteIndex < 0 || (remote != null && remote.id != requested.noteId)) {
        throw const SyncFailure(code: SyncErrorCode.unexpected);
      }
      final LocalNoteState local = current.notes[noteIndex];
      final PendingMutation blocked = copyEntry(
        current.outbox[entryIndex],
        blocked: true,
      );
      final List<PendingMutation> outbox = List<PendingMutation>.of(
        current.outbox,
      )..[entryIndex] = blocked;
      final List<LocalNoteState> notes = List<LocalNoteState>.of(current.notes)
        ..[noteIndex] = withStatus(local, NoteSyncStatus.conflict);
      final List<SyncConflict> conflicts =
          List<SyncConflict>.of(current.conflicts)
            ..removeWhere(
              (SyncConflict item) => item.noteId == requested.noteId,
            )
            ..add(
              SyncConflict(
                noteId: requested.noteId,
                remote: remote,
                local: local,
                pending: blocked,
                detectedAt: detectedAt,
              ),
            );
      return copyState(
        current,
        notes: notes,
        outbox: outbox,
        conflicts: conflicts,
      );
    });
    return updated.conflicts.any(
      (SyncConflict item) =>
          item.noteId == requested.noteId &&
          item.pending.mutationId == requested.mutationId,
    );
  }

  Future<bool> acknowledge(
    PendingMutation requested,
    SyncNoteSnapshot snapshot,
  ) async {
    var acknowledged = false;
    await update((current) {
      final int entryIndex = current.outbox.indexWhere(
        (PendingMutation item) => item.mutationId == requested.mutationId,
      );
      if (entryIndex < 0) return current;
      final int noteIndex = current.notes.indexWhere(
        (LocalNoteState note) => note.id == requested.noteId,
      );
      if (noteIndex < 0) {
        throw const SyncFailure(code: SyncErrorCode.unexpected);
      }
      final bool later = current.outbox.any(
        (PendingMutation item) =>
            item.noteId == requested.noteId &&
            item.mutationId != requested.mutationId,
      );
      final List<PendingMutation> outbox = current.outbox
          .where(
            (PendingMutation item) => item.mutationId != requested.mutationId,
          )
          .toList();
      final List<LocalNoteState> notes = List<LocalNoteState>.of(current.notes);
      final LocalNoteState local = notes[noteIndex];
      notes[noteIndex] = later
          ? LocalNoteState(
              id: local.id,
              ownerId: local.ownerId,
              title: local.title,
              content: local.content,
              createdAt: local.createdAt,
              updatedAt: local.updatedAt,
              deletedAt: local.deletedAt,
              serverRevision: snapshot.revision,
              status: local.status,
            )
          : fromRemote(snapshot, NoteSyncStatus.synced);
      acknowledged = true;
      return copyState(current, notes: notes, outbox: outbox);
    });
    return acknowledged;
  }

  Future<SyncPageApply> applyPage(
    SyncChangesPage page, {
    required String? expectedCursor,
  }) async {
    var pulled = 0;
    var changed = false;
    final LocalSyncState updated = await update((current) {
      if (current.cursor?.value != expectedCursor) return current;
      final List<LocalNoteState> notes = List<LocalNoteState>.of(current.notes);
      final List<SyncConflict> conflicts = List<SyncConflict>.of(
        current.conflicts,
      );
      for (final SyncNoteSnapshot snapshot in page.snapshots) {
        final int conflictIndex = conflicts.indexWhere(
          (SyncConflict item) => item.noteId == snapshot.id,
        );
        if (conflictIndex >= 0) {
          final SyncConflict conflict = conflicts[conflictIndex];
          if (snapshot.revision > (conflict.remote?.revision ?? 0)) {
            conflicts[conflictIndex] = SyncConflict(
              noteId: conflict.noteId,
              remote: snapshot,
              local: conflict.local,
              pending: conflict.pending,
              detectedAt: conflict.detectedAt,
            );
            changed = true;
          }
          continue;
        }
        if (current.outbox.any(
          (PendingMutation item) => item.noteId == snapshot.id,
        )) {
          continue;
        }
        final int noteIndex = notes.indexWhere(
          (LocalNoteState item) => item.id == snapshot.id,
        );
        if (noteIndex >= 0 &&
            snapshot.revision <= notes[noteIndex].serverRevision) {
          continue;
        }
        final LocalNoteState incoming = fromRemote(
          snapshot,
          NoteSyncStatus.synced,
        );
        if (noteIndex < 0) {
          notes.add(incoming);
        } else {
          notes[noteIndex] = incoming;
        }
        pulled++;
        changed = true;
      }
      final SyncCursor? cursor = page.nextCursor == null
          ? current.cursor
          : SyncCursor(page.nextCursor);
      if (!changed && cursor == current.cursor) {
        return current;
      }
      return copyState(
        current,
        notes: notes,
        conflicts: conflicts,
        cursor: cursor,
      );
    });
    final bool cursorMatched =
        updated.cursor?.value == expectedCursor ||
        (page.nextCursor != null && updated.cursor?.value == page.nextCursor);
    if (!cursorMatched) {
      return const SyncPageApply(cursorMatched: false, pulled: 0);
    }
    return SyncPageApply(cursorMatched: true, pulled: pulled);
  }

  LocalSyncState copyState(
    LocalSyncState current, {
    Iterable<LocalNoteState>? notes,
    Iterable<PendingMutation>? outbox,
    Iterable<SyncConflict>? conflicts,
    SyncCursor? cursor,
  }) => LocalSyncState(
    accountUserId: current.accountUserId,
    notes: notes ?? current.notes,
    outbox: outbox ?? current.outbox,
    conflicts: conflicts ?? current.conflicts,
    cursor: cursor ?? current.cursor,
  );

  PendingMutation copyEntry(
    PendingMutation entry, {
    int? retryCount,
    SyncErrorCode? lastError,
    bool? blocked,
  }) => PendingMutation(
    mutationId: entry.mutationId,
    noteId: entry.noteId,
    operation: entry.operation,
    baseRevision: entry.baseRevision,
    payload: entry.payload,
    createdAt: entry.createdAt,
    retryCount: retryCount ?? entry.retryCount,
    lastError: lastError ?? entry.lastError,
    blocked: blocked ?? entry.blocked,
  );

  LocalNoteState withStatus(LocalNoteState note, NoteSyncStatus status) =>
      LocalNoteState(
        id: note.id,
        ownerId: note.ownerId,
        title: note.title,
        content: note.content,
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
        serverRevision: note.serverRevision,
        deletedAt: note.deletedAt,
        status: status,
      );

  LocalNoteState fromRemote(SyncNoteSnapshot snapshot, NoteSyncStatus status) =>
      LocalNoteState(
        id: snapshot.id,
        ownerId: accountUserId,
        title: snapshot.title,
        content: snapshot.content,
        createdAt: snapshot.createdAt,
        updatedAt: snapshot.serverUpdatedAt,
        serverRevision: snapshot.revision,
        deletedAt: snapshot.deletedAt,
        status: status,
      );
}

final class SyncPageApply {
  const SyncPageApply({required this.cursorMatched, required this.pulled});
  final bool cursorMatched;
  final int pulled;
}
