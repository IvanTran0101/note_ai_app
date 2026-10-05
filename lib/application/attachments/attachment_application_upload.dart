part of 'attachment_application.dart';

extension _AttachmentApplicationUpload on AttachmentApplicationService {
  Future<NoteDto> _upload(AttachmentBinding binding, String cacheId) async {
    final draft = await drafts.load(binding, cacheId);
    _requireAttempt(binding, cacheId);
    var note = await _fresh(binding);
    _requireAttempt(binding, cacheId);
    final linked = note.attachments.where((item) => item.id == cacheId);
    if (linked.isNotEmpty) {
      _requireDescriptor(binding, draft, linked.single);
      // A previous local commit may have succeeded before marking the cache.
      // Recover it without uploading or appending another descriptor.
      if (isAssociated == null || await isAssociated!(binding, cacheId)) {
        await drafts.markLinked(binding, cacheId);
      }
      _requireAttempt(binding, cacheId);
      requestSync?.call(binding.actorId);
      return NoteDto.fromDomain(note);
    }
    AttachmentPolicy.validate(
      fileName: draft.fileName,
      mimeType: draft.mimeType,
      sizeBytes: draft.sizeBytes,
      existing: note.attachments,
    );
    if (note.contentRevision == 0) {
      requestSync?.call(binding.actorId);
      throw StateError(
        'Attachment is queued locally until the note create is acknowledged.',
      );
    }
    _requireAttempt(binding, cacheId);
    final verified = await upload(binding, draft, () async* {
      await for (final chunk in drafts.read(binding, draft)) {
        _requireAttempt(binding, cacheId);
        yield chunk;
        _requireAttempt(binding, cacheId);
      }
    });
    _requireAttempt(binding, cacheId);
    _requireDescriptor(binding, draft, verified);
    final updated = await notes.updateById(
      noteId: binding.note.noteId,
      ownerId: binding.note.ownerId,
      expectedAccountUserId: binding.actorId,
      canCommit: () {
        _requireAttempt(binding, cacheId);
        return true;
      },
      change: (fresh) {
        _requireNote(binding, fresh);
        _requireAttempt(binding, cacheId);
        final existing = fresh.attachments.where((item) => item.id == cacheId);
        if (existing.isEmpty) {
          AttachmentPolicy.validate(
            fileName: draft.fileName,
            mimeType: draft.mimeType,
            sizeBytes: draft.sizeBytes,
            existing: fresh.attachments,
          );
        }
        fresh.addAttachment(verified, now().toUtc());
        return fresh;
      },
    );
    _requireAttempt(binding, cacheId);
    note = updated;
    // Local Note + outbox is committed first. Failure here leaves a recoverable
    // queued draft, never a discarded file whose metadata was not saved.
    if (isAssociated == null) await drafts.markLinked(binding, cacheId);
    _requireAttempt(binding, cacheId);
    requestSync?.call(binding.actorId);
    return NoteDto.fromDomain(note);
  }

  void _requireDescriptor(
    AttachmentBinding binding,
    LocalAttachmentDraft draft,
    Attachment verified,
  ) {
    if (verified.id != draft.cacheId ||
        verified.noteId != binding.note.noteId ||
        verified.fileName != draft.fileName ||
        verified.mimeType != draft.mimeType ||
        verified.sizeBytes != draft.sizeBytes ||
        verified.sha256 != draft.sha256) {
      throw StateError('Server descriptor does not match the staged attempt.');
    }
  }
}
