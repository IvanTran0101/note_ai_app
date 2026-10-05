part of 'attachment_application.dart';

extension _AttachmentApplicationRemoval on AttachmentApplicationService {
  Future<NoteDto> _removeCaptured(AttachmentBinding binding, String id) async {
    var note = await _fresh(binding);
    final entries = note.attachments.where((item) => item.id == id);
    if (entries.isNotEmpty && drafts is AttachmentRemovalCache) {
      final cache = drafts as AttachmentRemovalCache;
      // Persist the user's intent before the only Note writer. A crash here
      // keeps ciphertext and retries the same removal instead of uploading it.
      await cache.prepareRemoval(binding, entries.single);
      _requireOwner(binding);
    }
    _cancelled.add(_attemptKey(binding, id));
    cancelMedia(binding.note.noteId, id);
    if (entries.isNotEmpty) {
      note = await notes.updateById(
        noteId: binding.note.noteId,
        ownerId: binding.note.ownerId,
        expectedAccountUserId: binding.actorId,
        canCommit: () {
          _requireOwner(binding);
          return true;
        },
        change: (fresh) {
          _requireNote(binding, fresh);
          fresh.removeAttachment(id, now().toUtc());
          return fresh;
        },
      );
    }
    _requireOwner(binding);
    if (drafts case final AttachmentTransferCache cache) {
      if (drafts is AttachmentRemovalCache &&
          (await (drafts as AttachmentRemovalCache).removalIds(binding))
              .contains(id)) {
        // Local manifest committed; delete local bytes, retain a tiny durable
        // server cancellation intent. Server refuses cancellation while linked.
        await cache.queueCancellation(binding, id);
      }
    }
    _requireOwner(binding);
    requestSync?.call(binding.actorId);
    _drainCancellations(binding);
    return NoteDto.fromDomain(note);
  }

  void _drainCancellations(AttachmentBinding binding) {
    if (remoteCancel == null || drafts is! AttachmentTransferCache) return;
    final key = jsonEncode([
      binding.actorId,
      binding.note.key,
      binding.sessionGeneration,
      binding.accessGeneration,
      binding.protection.revision,
    ]);
    if (!_cancellationDrains.add(key)) return;
    unawaited(() async {
      try {
        final cache = drafts as AttachmentTransferCache;
        for (final id in await cache.cancellationIds(binding)) {
          try {
            final fresh = await _fresh(binding);
            // Reconcile an explicit canonical cloud/conflict restore: keep its
            // immutable object. A local optimistic descriptor is insufficient.
            if (fresh.attachments.any((item) => item.id == id)) {
              if (isAssociated == null || !await isAssociated!(binding, id)) {
                continue;
              }
              _requireOwner(binding);
              await cache.finishCancellation(binding, id);
              continue;
            }
            // Crash during local deletion must finish before releasing quota.
            await cache.queueCancellation(binding, id);
            _requireOwner(binding);
            await remoteCancel!(binding, id);
            _requireOwner(binding);
            await cache.finishCancellation(binding, id);
          } on Object {
            // Offline/unlink ACK/authority loss retains the durable intent.
          }
        }
      } on Object {
        // Session changes and storage errors are retried under fresh authority.
      } finally {
        _cancellationDrains.remove(key);
      }
    }());
  }
}
