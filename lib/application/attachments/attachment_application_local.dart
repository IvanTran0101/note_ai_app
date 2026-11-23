part of 'attachment_application.dart';

extension _AttachmentApplicationLocal on AttachmentApplicationService {
  Future<LocalAttachmentDraft> _stage(
    String noteId,
    AttachmentInput input,
  ) async {
    try {
      final binding = await _capture(noteId);
      final note = await _fresh(binding);
      AttachmentPolicy.validate(
        fileName: input.fileName,
        mimeType: input.mimeType,
        sizeBytes: input.sizeBytes,
        existing: note.attachments,
      );
      final draft = await drafts.stage(
        binding,
        input,
        existing: note.attachments,
      );
      // A lock/session transition keeps durable ciphertext for a later retry,
      // but does not expose an obsolete result to the old UI session.
      _requireOwner(binding);
      return draft;
    } finally {
      await input.release?.call();
    }
  }

  /// Capture authority BEFORE opening a platform picker. A result from an old
  /// account/lock session must never be staged under a freshly captured actor.
  Future<void> _pickAndStage(
    String noteId,
    Future<List<AttachmentInput>> Function() pick, {
    Future<void> Function()? resumeProtected,
  }) async {
    var binding = await _capture(noteId);
    await _fresh(binding);
    final selected = await pick();
    // Cancellation may cause a lifecycle lock but never creates an attachment.
    if (selected.isEmpty) return;
    try {
      binding = await _resumePicker(binding, resumeProtected);
      for (final input in selected) {
        final note = await _fresh(binding);
        await drafts.stage(binding, input, existing: note.attachments);
        _requireOwner(binding);
      }
    } finally {
      var failed = false;
      for (final input in selected) {
        try {
          await input.release?.call();
        } on Object {
          failed = true;
        }
      }
      if (failed) throw StateError('Selected file cleanup failed.');
    }
  }

  Future<AttachmentBinding> _resumePicker(
    AttachmentBinding binding,
    Future<void> Function()? resumeProtected,
  ) async {
    if (binding.protection.enabled) {
      try {
        _requireOwner(binding);
      } on NoteSecurityFailure {
        if (resumeProtected == null) rethrow;
        await resumeProtected();
      }
    }
    {
      // Native picker pauses the Activity and locks M05 leases. Reacquire live
      // authority ONLY for the identical captured
      // actor/session/resource/content/protection/access epochs.
      final resumed = await _capture(binding.note.noteId);
      if (resumed.actorId != binding.actorId ||
          resumed.note != binding.note ||
          resumed.sessionGeneration != binding.sessionGeneration ||
          resumed.protection != binding.protection ||
          resumed.accessRevision != binding.accessRevision ||
          resumed.contentRevision != binding.contentRevision) {
        throw StateError('The picker authority changed.');
      }
      binding = resumed;
    }
    _requireOwner(binding);
    return binding;
  }

  /// Bounded local preview; no raw key, grant or filesystem path reaches UI.
  /// The original authority is rechecked for every chunk and at completion.
  Stream<List<int>> _readLocal(
    String noteId,
    String cacheId, {
    int start = 0,
    int? end,
  }) async* {
    final binding = await _capture(noteId);
    await _fresh(binding);
    final draft = await drafts.load(binding, cacheId);
    _requireOwner(binding);
    var completed = start;
    await for (final chunk in drafts.read(
      binding,
      draft,
      start: start,
      end: end,
    )) {
      _requireOwner(binding);
      completed += chunk.length;
      onReadProgress?.call(
        AttachmentProgress(cacheId, 'Reading', completed, draft.sizeBytes),
      );
      yield chunk;
    }
    _requireOwner(binding);
  }
}
