import '../../domain/notes/note_document.dart';
import 'local_note_state.dart';
import 'sync_snapshot.dart';
import 'sync_failure.dart';

/// An older response cannot erase an already typed document. Unavailable
/// metadata deliberately masks it; a readable body change needs typed presence.
NoteDocument? projectSyncDocument(
  SyncNoteSnapshot snapshot,
  LocalNoteState? previous,
) {
  if (!snapshot.contentAvailable || snapshot.isDeleted) return null;
  if (snapshot.includesDocument) return snapshot.document;
  if (previous?.document != null && previous!.content != snapshot.content) {
    throw const SyncFailure(
      code: SyncErrorCode.invalidMutation,
      detail: 'documentRequiresUpgrade',
    );
  }
  return previous?.document;
}
