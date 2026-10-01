import 'note.dart';

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
  /// Returns null when the note is absent or deleted. The update fails if the
  /// active account changed before the transaction commits.
  Future<Note?> updateById(
    String id, {
    required String expectedAccountUserId,
    required void Function(Note note) change,
  });

  /// Deletes the note with [id]. Succeeds without error when it is absent.
  Future<void> deleteById(String id);
}
