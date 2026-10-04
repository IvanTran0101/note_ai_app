part of 'note_repository.dart';

extension _NoteRepositoryUpdate on NoteRepository {
  Future<Note> _updateById({
    required String noteId,
    required String ownerId,
    required String expectedAccountUserId,
    required domain.NoteChange change,
    required domain.NoteCommitFence canCommit,
  }) {
    final context = _captureWrite();
    void fence() {
      if (context.account != expectedAccountUserId || !canCommit()) {
        throw const domain.NoteMutationCancelledException();
      }
      _requireWrite(context);
    }

    return _enqueue(() async {
      fence();
      Note? result;
      await _storeFor(expectedAccountUserId).update((state) {
        fence();
        final existing = state.notes
            .where(
              (n) => n.ownerId == ownerId && n.id == noteId && !n.isDeleted,
            )
            .firstOrNull;
        if (existing == null) throw const domain.NoteMutationMissingException();
        if (state.conflicts.any((c) => c.identity == existing.identity)) {
          throw StateError(
            'Resolve the sync conflict before editing this note.',
          );
        }
        final fresh = NoteRepository._toDomain(existing);
        _authorizeUpdate(fresh, expectedAccountUserId, NoteOperation.read);
        if (!identical(change(fresh), fresh)) {
          throw ArgumentError('Note change must return its fresh instance.');
        }
        fence();
        _validateUpdatedNote(fresh, existing, expectedAccountUserId);
        result = fresh;
        if (fresh.title == existing.title &&
            fresh.content == existing.content &&
            sameAttachments(fresh.attachments, existing.attachments) &&
            fresh.pinnedAt == existing.pinnedAt) {
          return state;
        }
        return _stateAfterSave(state, fresh, now());
      });
      fence();
      return result!;
    });
  }

  void _authorizeUpdate(Note note, String actor, NoteOperation operation) {
    if (!const NoteAccessPolicy().allows(
      actorId: actor,
      note: note.identity,
      share: note.share,
      operation: operation,
    )) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
    }
    if (!note.contentAvailable) throw const NoteContentUnavailable();
    _requireNoteAccess(note.id, note.ownerId, note.protection, operation);
  }

  void _validateUpdatedNote(Note note, LocalNoteState old, String actor) {
    if (note.identity != old.identity ||
        note.createdAt != old.createdAt ||
        note.protection != old.protection ||
        note.share != old.share ||
        note.contentRevision != old.serverRevision ||
        note.contentAvailable != old.contentAvailable) {
      throw ArgumentError(
        'A text/pin mutation cannot change resource authority.',
      );
    }
    if (note.pinnedAt != old.pinnedAt) {
      _authorizeUpdate(note, actor, NoteOperation.manage);
    }
    if (!sameAttachments(note.attachments, old.attachments)) {
      _authorizeUpdate(note, actor, NoteOperation.attachmentWrite);
    }
    if (note.title != old.title || note.content != old.content) {
      _authorizeUpdate(note, actor, NoteOperation.edit);
      if (note.title.trim().isEmpty || note.content.trim().isEmpty) {
        throw ArgumentError('Note text must not be blank.');
      }
    }
  }
}
