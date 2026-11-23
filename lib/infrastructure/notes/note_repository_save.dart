part of 'note_repository.dart';

/// Direct/legacy saves share the same durable transform as snapshot writes.
extension _NoteRepositorySave on NoteRepository {
  Future<void> _save(Note note, {Note? expected}) async {
    final context = _captureWrite();
    return _enqueue<void>(() async {
      final actor = _requireActiveAccountUserId();
      if (note.ownerId != actor && note.share == null) {
        throw ArgumentError('Note belongs to another account.');
      }
      await _storeFor(actor).update((current) {
        _requireWrite(context);
        if (current.conflicts.any((c) => c.identity == note.identity)) {
          throw StateError(
            'Resolve the sync conflict before editing this note.',
          );
        }
        final existing = NoteRepository._findNote(current, note.reference);
        _validateSaveSnapshot(existing, expected);
        _authorizeSave(note, existing, current, actor);
        return _stateAfterSave(current, note, now());
      });
    });
  }

  void _validateSaveSnapshot(LocalNoteState? existing, Note? expected) {
    if (expected == null) return;
    if (existing == null ||
        existing.identity != expected.identity ||
        existing.serverRevision != expected.contentRevision ||
        existing.updatedAt != expected.updatedAt ||
        existing.title != expected.title ||
        existing.content != expected.content ||
        existing.document != expected.document ||
        existing.pinnedAt != expected.pinnedAt ||
        !sameAttachments(existing.attachments, expected.attachments) ||
        existing.share != expected.share ||
        existing.protection != expected.protection ||
        !existing.contentAvailable) {
      throw const domain.NoteSnapshotChanged();
    }
  }

  void _authorizeSave(
    Note note,
    LocalNoteState? existing,
    LocalSyncState current,
    String actor,
  ) {
    if (!const NoteAccessPolicy().allows(
          actorId: actor,
          note: note.identity,
          share: existing?.share,
          operation: NoteOperation.edit,
        ) ||
        note.ownerId != actor &&
            (existing == null || existing.share != note.share)) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
    }
    _requireNoteAccess(
      note.id,
      note.ownerId,
      note.protection,
      NoteOperation.edit,
    );
    if (!note.contentAvailable ||
        existing != null && !existing.contentAvailable) {
      throw const NoteContentUnavailable();
    }
    if (existing != null && existing.protection != note.protection) {
      throw StateError('Refresh note protection before saving.');
    }
    if (existing?.document != null && note.document == null) {
      throw ArgumentError('A legacy writer cannot discard a rich document.');
    }
    if (existing?.isDeleted ?? false) {
      throw StateError('A deleted note cannot be restored with the same id.');
    }
    if (note.pinnedAt != existing?.pinnedAt) {
      _authorizeUpdate(note, actor, NoteOperation.manage);
    }
    if (!sameAttachments(note.attachments, existing?.attachments ?? const [])) {
      _authorizeUpdate(note, actor, NoteOperation.attachmentWrite);
    }
    _validateLabels(note, existing?.labelIds ?? const [], current, actor);
  }
}
