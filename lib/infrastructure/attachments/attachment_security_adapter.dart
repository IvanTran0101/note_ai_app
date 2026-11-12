import '../../application/attachments/attachment_binding.dart';
import '../../application/notes/note_access.dart';
import '../../domain/notes/note_access_policy.dart';
import '../../domain/notes/note_protection.dart';
import '../security/encrypted_sync_store.dart';
import '../security/note_security_runtime.dart';

/// Bridges binary staging/read to the existing M05/M06 actor, ACL and leases.
/// Keys remain inside Infrastructure; no passwords or grants enter metadata.
final class AttachmentSecurityAdapter {
  AttachmentSecurityAdapter({
    required this.security,
    required this.storeForAccount,
  });
  final NoteSecurityRuntime security;
  final EncryptedSyncStore Function(String actorId) storeForAccount;

  Future<AttachmentBinding> capture(String reference) async {
    final actor = security.session.requiredUserId;
    security.requireSession(actor);
    security.forAccount(actor);
    final session = security.session.sessionGeneration;
    final generation = security.accessGeneration;
    final state = await storeForAccount(actor).read();
    if (security.session.userId != actor ||
        security.session.sessionGeneration != session ||
        security.accessGeneration != generation) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
    final note = state.notes
        .where((n) => n.referenceFor(actor) == reference && !n.isDeleted)
        .firstOrNull;
    if (note == null ||
        !note.contentAvailable ||
        !const NoteAccessPolicy().allows(
          actorId: actor,
          note: note.identity,
          share: note.share,
          operation: NoteOperation.attachmentRead,
        )) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
    }
    final binding = AttachmentBinding(
      actorId: actor,
      note: note.identity,
      protection: note.protection,
      accessRevision: note.share?.accessRevision ?? 0,
      sessionGeneration: session,
      accessGeneration: generation,
      contentRevision: note.serverRevision,
    );
    requireAccess(binding, NoteOperation.attachmentRead);
    return binding;
  }

  void requireAccess(AttachmentBinding binding, NoteOperation operation) {
    security.requireSession(binding.actorId);
    if (security.session.sessionGeneration != binding.sessionGeneration ||
        security.accessGeneration != binding.accessGeneration) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
    if (operation != NoteOperation.attachmentRead &&
            operation != NoteOperation.attachmentWrite &&
            operation != NoteOperation.export ||
        operation != NoteOperation.attachmentRead &&
            binding.actorId != binding.note.ownerId) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
    }
    security.requireAccess(
      ownerId: binding.note.ownerId,
      noteId: binding.note.noteId,
      protection: binding.protection,
      operation: operation,
    );
  }
}
