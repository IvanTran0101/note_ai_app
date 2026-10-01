import 'note.dart';
import 'note_metadata.dart';

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

  /// Deletes the note with [id]. Succeeds without error when it is absent.
  Future<void> deleteById(String id);
}

/// Metadata-only query boundary, independent of content authorization.
abstract interface class INoteMetadataRepository {
  Future<NoteMetadata?> findMetadataById(String id);
  Future<List<NoteMetadata>> findMetadataByOwnerId(String ownerId);
}
