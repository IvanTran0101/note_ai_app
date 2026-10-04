import '../../domain/notes/note_identity.dart';
import '../../domain/notes/note_protection.dart';

/// Captured authority facts, never an unlock token or key. A live guard must
/// revalidate these facts before/after every asynchronous binary operation.
final class AttachmentBinding {
  AttachmentBinding({
    required this.actorId,
    required this.note,
    required this.protection,
    required this.accessRevision,
    required this.sessionGeneration,
    required this.contentRevision,
    this.accessGeneration = 0,
  }) {
    if (actorId.trim().isEmpty ||
        accessRevision < 0 ||
        sessionGeneration < 0 ||
        contentRevision < 0) {
      throw ArgumentError('Invalid attachment authority binding.');
    }
  }
  final String actorId;
  final NoteIdentity note;
  final NoteProtection protection;
  final int accessRevision;
  final int sessionGeneration;
  final int contentRevision;
  final int accessGeneration;
}
