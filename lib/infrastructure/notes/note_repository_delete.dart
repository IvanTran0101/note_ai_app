part of 'note_repository.dart';

extension _NoteRepositoryDelete on NoteRepository {
  Future<void> _deleteById(String id) {
    final context = _captureWrite();
    return _enqueue<void>(() async {
      final String accountUserId = _requireActiveAccountUserId();
      final ILocalSyncStore store = _storeFor(accountUserId);
      await store.update((LocalSyncState current) {
        _requireWrite(context);
        if (current.conflicts.any(
          (SyncConflict conflict) => conflict.noteId == id,
        )) {
          throw StateError(
            'Resolve the sync conflict before deleting this note.',
          );
        }
        final LocalNoteState? existing = NoteRepository._findNote(current, id);
        if (existing == null || existing.isDeleted) {
          // An absent or already tombstoned note is already deleted.
          return current;
        }
        _requireNoteAccess(
          id,
          accountUserId,
          existing.protection,
          NoteOperation.delete,
        );
        if (!existing.contentAvailable) throw const NoteContentUnavailable();
        final int pendingIndex = NoteRepository._lastPendingIndexFor(
          current,
          id,
        );
        final PendingMutation? pending = pendingIndex == -1
            ? null
            : current.outbox[pendingIndex];
        if (existing.serverRevision == 0 && pending == null) {
          // No server version and no queued create means this note is only a
          // local draft. Removing it locally cannot lose a remote delete.
          return NoteRepository._stateWith(
            current,
            notes: current.notes
                .where((LocalNoteState note) => note.id != id)
                .toList(growable: false),
            outbox: current.outbox,
          );
        }
        if (pending != null &&
            pending.operation == SyncMutationOperation.create &&
            existing.serverRevision == 0 &&
            NoteRepository._isUnsent(pending)) {
          // The create never reached the server, so dropping the note and its
          // mutation is the whole delete: no remote tombstone is needed.
          return NoteRepository._stateWith(
            current,
            notes: current.notes
                .where((LocalNoteState note) => note.id != id)
                .toList(growable: false),
            outbox: current.outbox
                .where(
                  (PendingMutation entry) =>
                      entry.mutationId != pending.mutationId,
                )
                .toList(growable: false),
          );
        }
        final DateTime timestamp = now();
        final LocalNoteState tombstone = LocalNoteState(
          id: existing.id,
          ownerId: existing.ownerId,
          title: '',
          content: '',
          createdAt: existing.createdAt,
          updatedAt: timestamp,
          serverRevision: existing.serverRevision,
          deletedAt: timestamp,
          status: NoteSyncStatus.pending,
          protection: existing.protection,
        );
        return NoteRepository._stateWith(
          current,
          notes: NoteRepository._notesWith(current.notes, tombstone),
          outbox: _outboxAfterDelete(
            current,
            existing,
            pendingIndex,
            timestamp,
          ),
        );
      });
    });
  }
}
