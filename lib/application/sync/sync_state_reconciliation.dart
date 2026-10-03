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
import 'sync_page_projection.dart';

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
              blocked:
                  failure.code == SyncErrorCode.invalidMutation ||
                  failure.code == SyncErrorCode.forbidden,
            );
      final List<LocalNoteState> notes =
          (failure.code == SyncErrorCode.invalidMutation ||
              failure.code == SyncErrorCode.forbidden)
          ? current.notes
                .map(
                  (LocalNoteState note) =>
                      note.identity == entry.mutation.identityFor(accountUserId)
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
        (LocalNoteState note) =>
            note.identity == requested.mutation.identityFor(accountUserId),
      );
      final SyncNoteSnapshot? remote = result.conflictRemote;
      if (noteIndex < 0 ||
          (remote != null &&
              remote.identityFor(accountUserId) !=
                  requested.mutation.identityFor(accountUserId))) {
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
              (SyncConflict item) =>
                  item.identity ==
                  requested.mutation.identityFor(accountUserId),
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
          item.identity == requested.mutation.identityFor(accountUserId) &&
          item.pending.mutationId == requested.mutationId,
    );
  }

  Future<bool> acknowledge(
    PendingMutation requested,
    SyncNoteSnapshot snapshot,
  ) async {
    if (snapshot.identityFor(accountUserId) !=
        requested.mutation.identityFor(accountUserId)) {
      throw const SyncFailure(code: SyncErrorCode.unexpected);
    }
    var acknowledged = false;
    await update((current) {
      final int entryIndex = current.outbox.indexWhere(
        (PendingMutation item) => item.mutationId == requested.mutationId,
      );
      if (entryIndex < 0) return current;
      final int noteIndex = current.notes.indexWhere(
        (LocalNoteState note) =>
            note.identity == requested.mutation.identityFor(accountUserId),
      );
      if (noteIndex < 0) {
        throw const SyncFailure(code: SyncErrorCode.unexpected);
      }
      final bool later = current.outbox.any(
        (PendingMutation item) =>
            item.mutation.identityFor(accountUserId) ==
                requested.mutation.identityFor(accountUserId) &&
            item.mutationId != requested.mutationId,
      );
      final List<PendingMutation> outbox = current.outbox
          .where(
            (PendingMutation item) => item.mutationId != requested.mutationId,
          )
          .toList();
      final List<LocalNoteState> notes = List<LocalNoteState>.of(current.notes);
      final LocalNoteState local = notes[noteIndex];
      notes[noteIndex] =
          later ||
              (requested.protectionChange != null && local.contentAvailable) ||
              (snapshot.protection.enabled &&
                  local.protection == snapshot.protection &&
                  local.contentAvailable)
          ? LocalNoteState(
              id: local.id,
              ownerId: local.ownerId,
              share: snapshot.share ?? local.share,
              title: local.title,
              content: local.content,
              createdAt: local.createdAt,
              updatedAt: local.updatedAt,
              pinnedAt: local.pinnedAt,
              deletedAt: local.deletedAt,
              serverRevision: snapshot.revision,
              status: later ? local.status : NoteSyncStatus.synced,
              protection:
                  outbox.any(
                    (m) =>
                        m.mutation.identityFor(accountUserId) ==
                            local.identity &&
                        m.protectionChange != null,
                  )
                  ? local.protection
                  : snapshot.protection,
              contentAvailable: local.contentAvailable,
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
      final projection = SyncPageProjection(current, fromRemote);
      for (final snapshot in page.snapshots) {
        projection.apply(snapshot);
      }
      changed = projection.changed;
      pulled = projection.pulled;
      final SyncCursor? cursor = page.nextCursor == null
          ? current.cursor
          : SyncCursor(page.nextCursor);
      if (!changed && cursor == current.cursor) {
        return current;
      }
      return copyState(
        current,
        notes: projection.notes,
        outbox: projection.outbox,
        conflicts: projection.conflicts,
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
    userPreferences: current.userPreferences,
  );

  PendingMutation copyEntry(
    PendingMutation entry, {
    int? retryCount,
    SyncErrorCode? lastError,
    bool? blocked,
  }) => PendingMutation(
    mutationId: entry.mutationId,
    noteId: entry.noteId,
    ownerId: entry.ownerId,
    accessRevision: entry.accessRevision,
    operation: entry.operation,
    baseRevision: entry.baseRevision,
    payload: entry.payload,
    protectionChange: entry.protectionChange,
    createdAt: entry.createdAt,
    retryCount: retryCount ?? entry.retryCount,
    lastError: lastError ?? entry.lastError,
    blocked: blocked ?? entry.blocked,
  );

  LocalNoteState withStatus(LocalNoteState note, NoteSyncStatus status) =>
      LocalNoteState(
        id: note.id,
        ownerId: note.ownerId,
        share: note.share,
        title: note.title,
        content: note.content,
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
        pinnedAt: note.pinnedAt,
        serverRevision: note.serverRevision,
        deletedAt: note.deletedAt,
        status: status,
        protection: note.protection,
        contentAvailable: note.contentAvailable,
      );

  LocalNoteState fromRemote(SyncNoteSnapshot snapshot, NoteSyncStatus status) =>
      LocalNoteState(
        id: snapshot.id,
        ownerId: snapshot.ownerId ?? accountUserId,
        share: snapshot.share,
        title: snapshot.title,
        content: snapshot.content,
        createdAt: snapshot.createdAt,
        updatedAt: snapshot.serverUpdatedAt,
        pinnedAt: snapshot.pinnedAt,
        serverRevision: snapshot.revision,
        deletedAt: snapshot.deletedAt,
        status: status,
        protection: snapshot.protection,
        contentAvailable: snapshot.contentAvailable,
      );
}

final class SyncPageApply {
  const SyncPageApply({required this.cursorMatched, required this.pulled});
  final bool cursorMatched;
  final int pulled;
}
