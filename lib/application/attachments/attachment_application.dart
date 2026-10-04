import 'dart:convert';

import '../../domain/notes/attachment.dart';
import '../../domain/notes/note.dart';
import '../../domain/notes/note_protection.dart';
import '../../domain/notes/note_repository.dart';
import '../notes/note_application.dart';
import 'attachment_binding.dart';
import 'attachment_draft_store.dart';
import 'attachment_input.dart';
import 'attachment_policy.dart';
import 'local_attachment_draft.dart';

/// The remote adapter must reuse draft.cacheId as its idempotent attempt ID,
/// verify bytes server-side, and return an immutable verified descriptor.
typedef UploadAttachment = Future<Attachment> Function(
  AttachmentBinding binding,
  LocalAttachmentDraft draft,
  Stream<List<int>> Function() openRead,
);

/// Local-first attachment use cases. Binary work never saves a stale Note or
/// creates a second note outbox. The live M05/M06 guard is mandatory; it must
/// check actor/session, current ACL and protection/access epochs on each call.
final class AttachmentApplicationService {
  AttachmentApplicationService({
    required this.notes,
    required this.drafts,
    required this.captureBinding,
    required this.requireAccess,
    required this.upload,
    required this.now,
    this.requestSync,
  });

  final INoteRepository notes;
  final AttachmentDraftStore drafts;
  final Future<AttachmentBinding> Function(String noteId) captureBinding;
  final void Function(AttachmentBinding, NoteOperation) requireAccess;
  final UploadAttachment upload;
  final DateTime Function() now;
  final RequestNoteSync? requestSync;
  final Map<String, Future<NoteDto>> _uploads = {};
  final Set<String> _cancelled = {};

  Future<AttachmentBinding> _capture(String noteId) async {
    final binding = await captureBinding(noteId);
    if (binding.note.noteId != noteId) {
      throw StateError('The attachment authority returned another note.');
    }
    _requireOwner(binding);
    return binding;
  }

  String _attemptKey(AttachmentBinding binding, String cacheId) =>
      jsonEncode([binding.actorId, binding.note.key, cacheId]);

  void _requireAttempt(AttachmentBinding binding, String cacheId) {
    _requireOwner(binding);
    if (_cancelled.contains(_attemptKey(binding, cacheId))) {
      throw StateError('Attachment upload was cancelled.');
    }
  }

  void _requireOwner(AttachmentBinding binding) {
    if (binding.actorId != binding.note.ownerId) {
      throw StateError('Only the owner may add or remove attachments.');
    }
    requireAccess(binding, NoteOperation.attachmentWrite);
  }

  void _requireNote(AttachmentBinding binding, Note note) {
    _requireOwner(binding);
    if (note.id != binding.note.noteId ||
        note.ownerId != binding.note.ownerId ||
        note.protection != binding.protection ||
        note.contentRevision != binding.contentRevision ||
        note.share != null &&
            note.share!.accessRevision != binding.accessRevision) {
      throw StateError('The canonical attachment note changed.');
    }
  }

  Future<Note> _fresh(AttachmentBinding binding) async {
    _requireOwner(binding);
    final note = await notes.findById(binding.note.noteId);
    _requireOwner(binding);
    if (note == null) throw NoteNotFoundException(binding.note.noteId);
    _requireNote(binding, note);
    return note;
  }

  Future<LocalAttachmentDraft> stage(
    String noteId,
    AttachmentInput input,
  ) async {
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
  }

  /// Capture authority BEFORE opening a platform picker. A result from an old
  /// account/lock session must never be staged under a freshly captured actor.
  Future<void> pickAndStage(
    String noteId,
    Future<List<AttachmentInput>> Function() pick,
  ) async {
    final binding = await _capture(noteId);
    await _fresh(binding);
    final selected = await pick();
    _requireOwner(binding);
    for (final input in selected) {
      final note = await _fresh(binding);
      await drafts.stage(binding, input, existing: note.attachments);
      _requireOwner(binding);
    }
  }

  /// Bounded local preview; no raw key, grant or filesystem path reaches UI.
  /// The original authority is rechecked for every chunk and at completion.
  Stream<List<int>> readLocal(
    String noteId,
    String cacheId, {
    int? end,
  }) async* {
    final binding = await _capture(noteId);
    await _fresh(binding);
    final draft = await drafts.load(binding, cacheId);
    _requireOwner(binding);
    await for (final chunk in drafts.read(binding, draft, end: end)) {
      _requireOwner(binding);
      yield chunk;
    }
    _requireOwner(binding);
  }

  Future<List<LocalAttachmentDraft>> pending(String noteId) async {
    final binding = await _capture(noteId);
    await _fresh(binding);
    await drafts.recoverIncomplete(binding);
    _requireOwner(binding);
    final ids = await drafts.pendingIds(binding);
    _requireOwner(binding);
    final result = <LocalAttachmentDraft>[];
    for (final id in ids) {
      result.add(await drafts.load(binding, id));
      _requireOwner(binding);
    }
    return List.unmodifiable(result);
  }

  Future<NoteDto> retry(String noteId, String cacheId) async {
    final binding = await _capture(noteId);
    _requireOwner(binding);
    _requireAttempt(binding, cacheId);
    final key = jsonEncode([
      binding.actorId,
      binding.note.key,
      binding.sessionGeneration,
      binding.accessRevision,
      binding.protection.enabled,
      binding.protection.revision,
      binding.contentRevision,
      cacheId,
    ]);
    final running = _uploads[key];
    if (running != null) {
      final result = await running;
      _requireAttempt(binding, cacheId);
      return result;
    }
    final work = _upload(binding, cacheId);
    _uploads[key] = work;
    try {
      return await work;
    } finally {
      _uploads.remove(key);
    }
  }

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
      await drafts.markLinked(binding, cacheId);
      _requireOwner(binding);
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
    final verified = await upload(
      binding,
      draft,
      () => drafts.read(binding, draft),
    );
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
    _requireOwner(binding);
    note = updated;
    // Local Note + outbox is committed first. Failure here leaves a recoverable
    // queued draft, never a discarded file whose metadata was not saved.
    await drafts.markLinked(binding, cacheId);
    _requireOwner(binding);
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

  Future<void> cancel(String noteId, String cacheId) async {
    final binding = await _capture(noteId);
    final note = await _fresh(binding);
    if (note.attachments.any((item) => item.id == cacheId)) {
      throw StateError('Remove the linked attachment through the note writer.');
    }
    _cancelled.add(_attemptKey(binding, cacheId));
    await drafts.cancelLocal(binding, cacheId);
    _requireOwner(binding);
  }

  Future<NoteDto> remove(String noteId, String attachmentId) async {
    final binding = await _capture(noteId);
    _requireOwner(binding);
    final updated = await notes.updateById(
      noteId: binding.note.noteId,
      ownerId: binding.note.ownerId,
      expectedAccountUserId: binding.actorId,
      canCommit: () {
        _requireOwner(binding);
        return true;
      },
      change: (fresh) {
        _requireNote(binding, fresh);
        fresh.removeAttachment(attachmentId, now().toUtc());
        return fresh;
      },
    );
    _requireOwner(binding);
    // Server cleanup follows the authoritative manifest sync, not a speculative
    // client-side S3 delete that could break another device's current snapshot.
    requestSync?.call(binding.actorId);
    return NoteDto.fromDomain(updated);
  }
}
