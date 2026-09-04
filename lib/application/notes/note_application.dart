import '../../domain/note_intelligence/summary.dart';
import '../../domain/notes/note.dart';
import '../../domain/notes/note_repository.dart';

/// Creates identifiers for newly created notes.
typedef NoteIdGenerator = String Function();

/// Supplies the current time to the application service.
typedef NoteClock = DateTime Function();

/// Summarizes note content without exposing a concrete provider to the
/// application layer.
typedef SummarizeNoteContent = Future<Summary> Function(String content);

/// A read-only application projection of the Note aggregate.
///
/// The DTO keeps presentation code independent from the domain aggregate's
/// mutation methods while preserving the fields needed by the Notes UI.
final class NoteDto {
  const NoteDto({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Creates a presentation-safe projection from a domain Note.
  factory NoteDto.fromDomain(Note note) {
    return NoteDto(
      id: note.id,
      ownerId: note.ownerId,
      title: note.title,
      content: note.content,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
    );
  }

  final String id;
  final String ownerId;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) {
    return other is NoteDto &&
        other.id == id &&
        other.ownerId == ownerId &&
        other.title == title &&
        other.content == content &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, ownerId, title, content, createdAt, updatedAt);

  @override
  String toString() {
    return 'NoteDto(id: $id, ownerId: $ownerId, title: $title, '
        'content: $content, createdAt: $createdAt, updatedAt: $updatedAt)';
  }
}

/// Raised when an application operation targets a note that does not exist.
final class NoteNotFoundException implements Exception {
  const NoteNotFoundException(this.noteId);

  final String noteId;

  @override
  String toString() => 'NoteNotFoundException: note "$noteId" was not found';
}

/// Raised when the current local owner attempts to access another owner's
/// note.
final class NoteOwnershipException implements Exception {
  const NoteOwnershipException({
    required this.noteId,
    required this.expectedOwnerId,
    required this.actualOwnerId,
  });

  final String noteId;
  final String expectedOwnerId;
  final String actualOwnerId;

  @override
  String toString() {
    return 'NoteOwnershipException: note "$noteId" belongs to '
        '"$actualOwnerId", not "$expectedOwnerId"';
  }
}

/// Application use cases for the Note aggregate.
///
/// This service coordinates domain behavior and persistence. It deliberately
/// contains no file, JSON, Flutter, FFI, or concrete AI-provider concerns.
/// The injected clock is normalized to UTC at this boundary so notes created
/// or mutated through the application use cases have stable persisted times.
final class NoteApplicationService {
  NoteApplicationService({
    required this.noteRepository,
    required this.ownerId,
    required this.generateId,
    required this.now,
    required this.summarizeContent,
  });

  final INoteRepository noteRepository;
  final String ownerId;
  final NoteIdGenerator generateId;
  final NoteClock now;
  final SummarizeNoteContent summarizeContent;

  /// Lists the notes owned by the configured local owner.
  Future<List<NoteDto>> listNotes() async {
    final List<Note> notes = await noteRepository.findByOwnerId(ownerId);
    return notes.map(NoteDto.fromDomain).toList(growable: false);
  }

  /// Creates and persists a new Note aggregate.
  Future<NoteDto> createNote({
    required String title,
    required String content,
  }) async {
    final Note note = Note.create(
      id: generateId(),
      ownerId: ownerId,
      title: title,
      content: content,
      now: now().toUtc(),
    );
    await noteRepository.save(note);
    return NoteDto.fromDomain(note);
  }

  /// Renames an owned note and persists the changed aggregate.
  Future<NoteDto> renameNote({
    required String noteId,
    required String title,
  }) async {
    final Note note = await _requireOwnedNote(noteId);
    note.rename(title, now().toUtc());
    await noteRepository.save(note);
    return NoteDto.fromDomain(note);
  }

  /// Replaces the content of an owned note and persists the changed
  /// aggregate.
  Future<NoteDto> replaceContent({
    required String noteId,
    required String content,
  }) async {
    final Note note = await _requireOwnedNote(noteId);
    note.replaceContent(content, now().toUtc());
    await noteRepository.save(note);
    return NoteDto.fromDomain(note);
  }

  /// Deletes an owned note.
  Future<void> deleteNote(String noteId) async {
    await _requireOwnedNote(noteId);
    await noteRepository.deleteById(noteId);
  }

  /// Summarizes an owned note without mutating or persisting it.
  Future<Summary> summarizeNote(String noteId) async {
    final Note note = await _requireOwnedNote(noteId);
    return summarizeContent(note.content);
  }

  Future<Note> _requireOwnedNote(String noteId) async {
    final Note? note = await noteRepository.findById(noteId);
    if (note == null) {
      throw NoteNotFoundException(noteId);
    }
    if (note.ownerId != ownerId) {
      throw NoteOwnershipException(
        noteId: noteId,
        expectedOwnerId: ownerId,
        actualOwnerId: note.ownerId,
      );
    }
    return note;
  }
}
