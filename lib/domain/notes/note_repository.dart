import 'note.dart';
import 'note_metadata.dart';

/// Recipient projections stay in the actor store with canonical owner intact.
abstract interface class ISharedNoteRepository {
  Future<List<Note>> findSharedWith(String actorId);
}

/// Atomic compare-and-save for editor snapshots, including local concurrency.
abstract interface class INoteSnapshotRepository {
  Future<void> saveSnapshot(Note note, Note expected);
}

final class NoteSnapshotChanged implements Exception {
  const NoteSnapshotChanged();
}

/// Persistence contract for the Note aggregate.
///
/// Implementations belong to Infrastructure. This contract does not prescribe
/// a database, cache, network client, or serialization format.
abstract interface class INoteRepository {
  /// Returns the note with [id], or `null` when it does not exist.
  Future<Note?> findById(String id);

  /// Returns all notes owned by [ownerId]. Returns an empty list when none
  /// exist.
  Future<List<Note>> findByOwnerId(String ownerId);

  /// Creates or replaces a note using [Note.id] as its identity.
  Future<void> save(Note note);

  /// Atomically changes the fresh note inside its account store transaction.
  /// Throws [NoteMutationMissingException] when absent or deleted. The caller's
  /// commit fence and active account/session must remain valid at commit time.
  Future<Note> updateById({
    required String noteId,
    required String ownerId,
    required String expectedAccountUserId,
    required NoteChange change,
    required NoteCommitFence canCommit,
  });

  /// Deletes the note with [id]. Succeeds without error when it is absent.
  Future<void> deleteById(String id);
}

/// Metadata-only query boundary, independent of content authorization.
abstract interface class INoteMetadataRepository {
  Future<NoteMetadata?> findMetadataById(String id);
  Future<List<NoteMetadata>> findMetadataByOwnerId(String ownerId);
}

/// Advertised only after the writer can persist the complete document atomically.
abstract interface class INoteDocumentRepository implements INoteRepository {
  int get documentVersion;
}

typedef NoteChange = Note Function(Note current);
typedef NoteCommitFence = bool Function();

final class NoteMutationCancelledException implements Exception {
  const NoteMutationCancelledException();
}

final class NoteMutationMissingException implements Exception {
  const NoteMutationMissingException();
}
