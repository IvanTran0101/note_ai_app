part of 'note_repository.dart';

extension _NoteRepositoryMutations on NoteRepository {
  LocalSyncState _stateAfterSave(
    LocalSyncState current,
    Note note,
    DateTime timestamp,
  ) {
    final LocalNoteState? existing = NoteRepository._findNote(
      current,
      note.reference,
    );
    if (existing == null) {
      // A new local note starts unacknowledged and queues one create.
      return NoteRepository._stateWith(
        current,
        notes: <LocalNoteState>[
          ...current.notes,
          NoteRepository._toLocalNote(
            note,
            serverRevision: 0,
            status: NoteSyncStatus.pending,
          ),
        ],
        outbox: <PendingMutation>[
          ...current.outbox,
          _pendingMutation(
            note: note,
            noteId: note.id,
            operation: SyncMutationOperation.create,
            baseRevision: 0,
            payload: NoteRepository._payloadOf(note),
            timestamp: timestamp,
          ),
        ],
      );
    }
    return NoteRepository._stateWith(
      current,
      notes: NoteRepository._notesWith(
        current.notes,
        NoteRepository._toLocalNote(
          note,
          serverRevision: existing.serverRevision,
          status: NoteSyncStatus.pending,
        ),
      ),
      outbox: _outboxAfterSave(current, note, existing, timestamp),
    );
  }

  List<PendingMutation> _outboxAfterSave(
    LocalSyncState current,
    Note note,
    LocalNoteState existing,
    DateTime timestamp,
  ) {
    final SyncNotePayload payload = NoteRepository._payloadOf(note);
    if (current.outbox.any(
      (PendingMutation entry) =>
          entry.mutation.identityFor(current.accountUserId) == note.identity &&
          entry.blocked &&
          entry.lastError == SyncErrorCode.invalidMutation &&
          !current.outbox.any(
            (m) =>
                m.mutation.identityFor(current.accountUserId) ==
                    note.identity &&
                m.protectionChange != null,
          ),
    )) {
      // An explicit edit repairs a rejected request with a fresh id and the
      // last acknowledged revision; successors of that request cannot run.
      return <PendingMutation>[
        ...current.outbox.where(
          (PendingMutation entry) =>
              entry.mutation.identityFor(current.accountUserId) !=
              note.identity,
        ),
        _pendingMutation(
          note: note,
          noteId: note.id,
          operation: existing.serverRevision == 0
              ? SyncMutationOperation.create
              : SyncMutationOperation.update,
          baseRevision: existing.serverRevision,
          payload: payload,
          timestamp: timestamp,
        ),
      ];
    }
    final int index = NoteRepository._lastPendingIndexFor(
      current,
      note.reference,
    );
    if (index == -1) {
      // Nothing is queued yet: base the update on the acknowledged revision.
      return <PendingMutation>[
        ...current.outbox,
        _pendingMutation(
          note: note,
          noteId: note.id,
          operation: SyncMutationOperation.update,
          baseRevision: existing.serverRevision,
          payload: payload,
          timestamp: timestamp,
        ),
      ];
    }
    final PendingMutation last = current.outbox[index];
    if (last.operation == SyncMutationOperation.delete) {
      throw StateError('A queued delete cannot be undone with the same id.');
    }
    if (!NoteRepository._isUnsent(last)) {
      // The entry may already have been seen by the server, so it stays
      // byte-for-byte identical and the edit becomes the next queued mutation
      // at the next predicted revision. Its id remains stable for retries.
      return <PendingMutation>[
        ...current.outbox,
        _pendingMutation(
          note: note,
          noteId: note.id,
          operation: SyncMutationOperation.update,
          baseRevision: last.baseRevision + 1,
          payload: payload,
          timestamp: timestamp,
        ),
      ];
    }
    // Unsent coalescing keeps the queue position, the base revision, and the
    // mutation id, while the payload always reflects the latest edit.
    final PendingMutation coalesced = PendingMutation(
      mutationId: last.mutationId,
      noteId: note.id,
      operation: last.operation,
      baseRevision: last.baseRevision,
      payload: payload,
      ownerId: last.ownerId,
      accessRevision: last.accessRevision,
      protectionChange: last.protectionChange,
      createdAt: last.createdAt,
    );
    return NoteRepository._outboxWithReplacement(
      current.outbox,
      index,
      coalesced,
    );
  }

  List<PendingMutation> _outboxAfterDelete(
    LocalSyncState current,
    LocalNoteState note,
    int pendingIndex,
    DateTime timestamp,
  ) {
    if (pendingIndex == -1) {
      return <PendingMutation>[
        ...current.outbox,
        _pendingMutation(
          noteId: note.id,
          operation: SyncMutationOperation.delete,
          baseRevision: note.serverRevision,
          timestamp: timestamp,
        ),
      ];
    }
    final PendingMutation last = current.outbox[pendingIndex];
    if (last.operation == SyncMutationOperation.delete) {
      // The delete is already queued; a second one would be redundant.
      return current.outbox;
    }
    if (!NoteRepository._isUnsent(last) || last.protectionChange != null) {
      return <PendingMutation>[
        ...current.outbox,
        _pendingMutation(
          noteId: note.id,
          operation: SyncMutationOperation.delete,
          baseRevision: last.baseRevision + 1,
          timestamp: timestamp,
        ),
      ];
    }
    // Unsent coalescing: an update followed by a delete is just the delete,
    // reusing the mutation id and base revision the server has never seen.
    final int baseRevision = last.operation == SyncMutationOperation.create
        ? note.serverRevision
        : last.baseRevision;
    return NoteRepository._outboxWithReplacement(
      current.outbox,
      pendingIndex,
      PendingMutation(
        mutationId: last.mutationId,
        noteId: note.id,
        operation: SyncMutationOperation.delete,
        baseRevision: baseRevision,
        createdAt: last.createdAt,
      ),
    );
  }

  PendingMutation _pendingMutation({
    Note? note,
    required String noteId,
    required SyncMutationOperation operation,
    required int baseRevision,
    SyncNotePayload? payload,
    required DateTime timestamp,
  }) {
    return PendingMutation(
      mutationId: generateMutationId(),
      noteId: noteId,
      operation: operation,
      baseRevision: baseRevision,
      payload: payload,
      createdAt: timestamp,
      ownerId: note != null && note.ownerId != _requireActiveAccountUserId()
          ? note.ownerId
          : null,
      accessRevision: note?.share?.accessRevision,
    );
  }
}
