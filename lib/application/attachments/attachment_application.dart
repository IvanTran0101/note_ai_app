import 'dart:async';
import 'dart:convert';

import '../../domain/notes/attachment.dart';
import '../../domain/notes/note.dart';
import '../../domain/notes/note_protection.dart';
import '../../domain/notes/note_repository.dart';
import '../notes/note_application.dart';
import '../notes/note_access.dart';
import 'attachment_binding.dart';
import 'attachment_draft_store.dart';
import 'attachment_input.dart';
import 'attachment_policy.dart';
import 'local_attachment_draft.dart';
import 'attachment_transfer.dart';
import 'attachment_media.dart';

part 'attachment_application_read.dart';
part 'attachment_application_media.dart';
part 'attachment_application_upload.dart';
part 'attachment_application_removal.dart';
part 'attachment_application_local.dart';

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
    this.remoteRead,
    this.remoteExportRead,
    this.mediaBridge,
    this.cancelRemoteRead,
    this.remoteCancel,
    this.isAssociated,
    this.progress = const Stream.empty(),
    this.onReadProgress,
  });

  final INoteRepository notes;
  final AttachmentDraftStore drafts;
  final Future<AttachmentBinding> Function(String noteId) captureBinding;
  final void Function(AttachmentBinding, NoteOperation) requireAccess;
  final UploadAttachment upload;
  final DateTime Function() now;
  final RequestNoteSync? requestSync;
  final ReadRemoteAttachment? remoteRead;
  final ReadRemoteAttachment? remoteExportRead;
  final AttachmentMediaBridge? mediaBridge;
  final void Function(AttachmentBinding, String)? cancelRemoteRead;
  final CancelRemoteAttachment? remoteCancel;
  final Future<bool> Function(AttachmentBinding, String)? isAssociated;
  final Stream<AttachmentProgress> progress;
  final void Function(AttachmentProgress)? onReadProgress;
  final Map<String, Future<NoteDto>> _uploads = {};
  final Set<String> _cancelled = {};
  final Map<String, _AttachmentMediaLease> _mediaLeases = {};
  final Map<String, Set<_AttachmentMediaLease>> _readLeases = {};
  final Set<String> _cancellationDrains = {};

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

  Future<LocalAttachmentDraft> stage(String noteId, AttachmentInput input) =>
      _stage(noteId, input);
  Future<void> pickAndStage(
    String noteId,
    Future<List<AttachmentInput>> Function() pick, {
    Future<void> Function()? resumeProtected,
  }) => _pickAndStage(noteId, pick, resumeProtected: resumeProtected);
  Stream<List<int>> readLocal(
    String noteId,
    String cacheId, {
    int start = 0,
    int? end,
  }) => _readLocal(noteId, cacheId, start: start, end: end);

  Future<List<LocalAttachmentDraft>> pending(String noteId) async {
    final binding = await _capture(noteId);
    await _fresh(binding);
    if (drafts case final AttachmentRemovalCache cache) {
      for (final id in await cache.removalIds(binding)) {
        await _removeCaptured(binding, id);
      }
    }
    _drainCancellations(binding);
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

  Future<void> cancel(String noteId, String cacheId) async {
    final binding = await _capture(noteId);
    final note = await _fresh(binding);
    if (note.attachments.any((item) => item.id == cacheId)) {
      throw StateError('Remove the linked attachment through the note writer.');
    }
    _cancelled.add(_attemptKey(binding, cacheId));
    cancelMedia(noteId, cacheId);
    if (remoteCancel != null && drafts is AttachmentTransferCache) {
      final cache = drafts as AttachmentTransferCache;
      await cache.queueCancellation(binding, cacheId);
      _drainCancellations(binding);
    } else {
      await drafts.cancelLocal(binding, cacheId);
    }
    _requireOwner(binding);
  }

  Future<NoteDto> remove(String noteId, String attachmentId) async {
    final binding = await _capture(noteId);
    return _removeCaptured(binding, attachmentId);
  }

  Stream<List<int>> read(
    String reference,
    Attachment attachment, {
    int start = 0,
    int? end,
  }) => readAssociated(reference, attachment, start: start, end: end);
  Future<bool> ready(String reference, Attachment attachment) =>
      associatedReady(reference, attachment);
  Future<AttachmentMediaHandle> openMedia(
    String reference,
    Attachment attachment,
  ) => _openMedia(reference, attachment: attachment);
  Future<AttachmentMediaHandle> openPendingMedia(
    String reference,
    LocalAttachmentDraft draft,
  ) => _openMedia(reference, draft: draft);
  Future<AttachmentMediaHandle> openExport(
    String reference,
    Attachment attachment,
  ) => _openMedia(reference, attachment: attachment, exportFile: true);
  void cancelMedia(String reference, String attachmentId) {
    final key = jsonEncode([reference, attachmentId]);
    _mediaLeases[key]?.cancel();
    for (final read in _readLeases[key] ?? <_AttachmentMediaLease>{}) {
      read.cancel();
    }
  }
}
