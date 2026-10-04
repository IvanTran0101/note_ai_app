part of 'attachment_application.dart';

extension _AttachmentApplicationRead on AttachmentApplicationService {
  Future<AttachmentBinding> _readBinding(
    String reference,
    Attachment attachment,
  ) async {
    final b = await captureBinding(reference);
    if (reference != b.note.referenceFor(b.actorId) ||
        attachment.noteId != b.note.noteId) {
      throw StateError('Invalid attachment note.');
    }
    requireAccess(b, NoteOperation.attachmentRead);
    final note = await notes.findById(reference);
    requireAccess(b, NoteOperation.attachmentRead);
    if (note == null ||
        note.identity != b.note ||
        note.protection != b.protection ||
        (note.share?.accessRevision ?? 0) != b.accessRevision ||
        !note.attachments.contains(attachment)) {
      throw StateError(
        'Attachment is no longer associated with a readable note.',
      );
    }
    return b;
  }

  Stream<List<int>> readAssociated(
    String reference,
    Attachment attachment, {
    int start = 0,
    int? end,
  }) async* {
    final b = await _readBinding(reference, attachment);
    Stream<List<int>> missing(
      AttachmentBinding _,
      Attachment _, {
      int start = 0,
      int? end,
    }) async* {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
    }

    final cache = drafts;
    final source = cache is AttachmentTransferCache
        ? (cache as AttachmentTransferCache).readAssociated(
            b,
            attachment,
            remoteRead ?? missing,
            start: start,
            end: end,
          )
        : (remoteRead ?? missing)(b, attachment, start: start, end: end);
    await for (final chunk in source) {
      requireAccess(b, NoteOperation.attachmentRead);
      yield chunk;
    }
    requireAccess(b, NoteOperation.attachmentRead);
  }

  Future<bool> associatedReady(String reference, Attachment attachment) async {
    final b = await _readBinding(reference, attachment);
    if (b.actorId != b.note.ownerId) return true;
    final cache = drafts;
    if (cache is AttachmentTransferCache &&
        await (cache as AttachmentTransferCache).isLinked(b, attachment.id)) {
      return true;
    }
    try {
      if (isAssociated != null && await isAssociated!(b, attachment.id)) {
        if (cache is AttachmentTransferCache) {
          try {
            await drafts.markLinked(b, attachment.id);
          } on Object {
            requireAccess(b, NoteOperation.attachmentRead);
          }
        }
        return true;
      }
    } on Object {
      requireAccess(b, NoteOperation.attachmentRead);
    }
    return false;
  }
}
