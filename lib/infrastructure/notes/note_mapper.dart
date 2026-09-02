import '../../domain/notes/note.dart';
import 'note_record.dart';

/// Maps the Note aggregate to and from its persistence representation.
///
/// Keeping this translation in Infrastructure prevents the Domain layer from
/// depending on JSON, database, or storage concerns.
abstract final class NoteMapper {
  /// Converts a domain aggregate to a persistence record.
  static NoteRecord toRecord(Note note) {
    return NoteRecord(
      id: note.id,
      ownerId: note.ownerId,
      title: note.title,
      content: note.content,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
    );
  }

  /// Reconstitutes a domain aggregate from a persistence record.
  static Note toDomain(NoteRecord record) {
    return Note.reconstitute(
      id: record.id,
      ownerId: record.ownerId,
      title: record.title,
      content: record.content,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    );
  }
}
