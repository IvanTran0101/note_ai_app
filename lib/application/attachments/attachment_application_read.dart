part of 'attachment_application.dart';

extension _AttachmentApplicationRead on AttachmentApplicationService {
  void _requireSameReader(AttachmentBinding b, AttachmentBinding current) {
    if (current.actorId != b.actorId ||
        current.note != b.note ||
        current.sessionGeneration != b.sessionGeneration ||
        current.accessGeneration != b.accessGeneration ||
        current.protection != b.protection ||
        current.accessRevision != b.accessRevision) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
  }

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
    bool exportFile = false,
  }) async* {
    final b = await _readBinding(reference, attachment);
    if (exportFile) requireAccess(b, NoteOperation.export);
    Stream<List<int>> missing(
      AttachmentBinding _,
      Attachment _, {
      int start = 0,
      int? end,
    }) async* {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
    }

    final cache = drafts;
    final remote = exportFile ? remoteExportRead : remoteRead;
    final source = cache is AttachmentTransferCache
        ? (cache as AttachmentTransferCache).readAssociated(
            b,
            attachment,
            remote ?? missing,
            start: start,
            end: end,
          )
        : (remote ?? missing)(b, attachment, start: start, end: end);
    final key = jsonEncode([reference, attachment.id]);
    final lease = _AttachmentMediaLease(
      () => cancelRemoteRead?.call(b, attachment.id),
    );
    (_readLeases[key] ??= {}).add(lease);
    void guard() {
      if (lease.cancelled) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
      }
      requireAccess(b, NoteOperation.attachmentRead);
      if (exportFile) requireAccess(b, NoteOperation.export);
    }

    try {
      var completed = start;
      await for (final chunk in source) {
        try {
          final current = await _readBinding(reference, attachment);
          _requireSameReader(b, current);
          guard();
          completed += chunk.length;
          onReadProgress?.call(
            AttachmentProgress(
              attachment.id,
              exportFile ? 'Saving' : 'Reading',
              completed,
              attachment.sizeBytes,
            ),
          );
        } on Object {
          chunk.fillRange(0, chunk.length, 0);
          rethrow;
        }
        yield chunk;
      }
      guard();
    } finally {
      _readLeases[key]?.remove(lease);
      if (_readLeases[key]?.isEmpty ?? false) _readLeases.remove(key);
    }
  }

  Future<bool> associatedReady(String reference, Attachment attachment) async {
    final b = await _readBinding(reference, attachment);
    if (b.actorId != b.note.ownerId) return true;
    final cache = drafts;
    if (cache is AttachmentRemovalCache &&
        (await (cache as AttachmentRemovalCache).removalIds(b))
            .contains(attachment.id)) {
      return false;
    }
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
