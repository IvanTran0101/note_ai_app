import 'note_identity.dart';
import 'note_protection.dart';
import 'note_role.dart';
import 'note_share_grant.dart';

/// Business permission only. M05 unlock and server authorization remain required.
final class NoteAccessPolicy {
  const NoteAccessPolicy();
  bool allows({
    required String actorId,
    required NoteIdentity note,
    required NoteOperation operation,
    NoteShareGrant? share,
  }) {
    if (actorId.isEmpty) return false;
    if (actorId == note.ownerId) return true;
    if (share == null ||
        share.note != note ||
        !share.isActive ||
        share.recipientId != actorId) {
      return false;
    }
    return switch (operation) {
      NoteOperation.read ||
      NoteOperation.summary ||
      NoteOperation.attachmentRead => true,
      NoteOperation.edit => share.role == NoteRole.editor,
      NoteOperation.delete ||
      NoteOperation.manage ||
      NoteOperation.export ||
      NoteOperation.attachmentWrite => false,
    };
  }
}
