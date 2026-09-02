import 'dart:async';

import '../../domain/notes/note.dart';
import '../../domain/notes/note_repository.dart' as domain;
import 'database_context.dart';
import 'note_mapper.dart';
import 'note_record.dart';

/// Infrastructure implementation of the domain's [domain.INoteRepository].
///
/// The repository maps between the Note aggregate and persistence records. It
/// owns no business rules: Note remains responsible for its own mutations,
/// while this class only performs CRUD and ordering/concurrency coordination.
final class NoteRepository implements domain.INoteRepository {
  NoteRepository({required this.databaseContext});

  final DatabaseContext databaseContext;

  /// Serializes repository operations so concurrent read-modify-write calls
  /// cannot overwrite each other's changes. Reads also use this queue and
  /// therefore observe all preceding mutations.
  Future<void> _operationTail = Future<void>.value();

  @override
  Future<Note?> findById(String id) {
    return _enqueue<Note?>(() async {
      final List<NoteRecord> records = await databaseContext.readNotes();
      for (final NoteRecord record in records) {
        if (record.id == id) {
          return NoteMapper.toDomain(record);
        }
      }
      return null;
    });
  }

  @override
  Future<List<Note>> findByOwnerId(String ownerId) {
    return _enqueue<List<Note>>(() async {
      final List<NoteRecord> records = await databaseContext.readNotes();
      return List<Note>.unmodifiable(
        records
            .where((NoteRecord record) => record.ownerId == ownerId)
            .map(NoteMapper.toDomain),
      );
    });
  }

  @override
  Future<void> save(Note note) {
    return _enqueue<void>(() async {
      final List<NoteRecord> records = List<NoteRecord>.of(
        await databaseContext.readNotes(),
      );
      final NoteRecord replacement = NoteMapper.toRecord(note);
      final int existingIndex = records.indexWhere(
        (NoteRecord record) => record.id == note.id,
      );
      if (existingIndex == -1) {
        records.add(replacement);
      } else {
        records[existingIndex] = replacement;
      }
      await databaseContext.writeNotes(records);
    });
  }

  @override
  Future<void> deleteById(String id) {
    return _enqueue<void>(() async {
      final List<NoteRecord> records = List<NoteRecord>.of(
        await databaseContext.readNotes(),
      );
      records.removeWhere((NoteRecord record) => record.id == id);
      await databaseContext.writeNotes(records);
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final Future<void> previous = _operationTail;
    final Completer<void> release = Completer<void>();
    _operationTail = release.future;
    return previous.then((_) async {
      try {
        return await operation();
      } finally {
        release.complete();
      }
    });
  }
}

/// Creates the native file-backed Note repository.
///
/// The composition root can inject a fake [DatabaseContext] in tests. This
/// factory is intentionally not wired into `main.dart` during M4.2.
domain.INoteRepository createNoteRepository({
  DatabaseContext? databaseContext,
}) {
  return NoteRepository(
    databaseContext: databaseContext ?? FileDatabaseContext(),
  );
}
