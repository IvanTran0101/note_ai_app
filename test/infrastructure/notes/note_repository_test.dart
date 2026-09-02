import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/domain/notes/note_repository.dart' as domain;
import 'package:note_ai_app/infrastructure/notes/database_context.dart';
import 'package:note_ai_app/infrastructure/notes/note_mapper.dart';
import 'package:note_ai_app/infrastructure/notes/note_record.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';

Note _note({
  required String id,
  String ownerId = 'owner-1',
  String title = 'Title',
  String content = 'Content',
  int minute = 0,
}) {
  return Note.create(
    id: id,
    ownerId: ownerId,
    title: title,
    content: content,
    now: DateTime.utc(2026, 9, 2, 10, minute),
  );
}

final class _FakeDatabaseContext implements DatabaseContext {
  _FakeDatabaseContext({Iterable<NoteRecord> initial = const <NoteRecord>[]})
    : records = List<NoteRecord>.of(initial);

  List<NoteRecord> records;
  int activeOperations = 0;
  int maximumActiveOperations = 0;

  @override
  Future<List<NoteRecord>> readNotes() async {
    _enterOperation();
    try {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      return List<NoteRecord>.of(records);
    } finally {
      _leaveOperation();
    }
  }

  @override
  Future<void> writeNotes(Iterable<NoteRecord> notes) async {
    _enterOperation();
    try {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      records = List<NoteRecord>.of(notes);
    } finally {
      _leaveOperation();
    }
  }

  void _enterOperation() {
    activeOperations++;
    if (activeOperations > maximumActiveOperations) {
      maximumActiveOperations = activeOperations;
    }
  }

  void _leaveOperation() {
    activeOperations--;
  }
}

final class _BlockingWriteContext implements DatabaseContext {
  _BlockingWriteContext({Iterable<NoteRecord> initial = const <NoteRecord>[]})
    : records = List<NoteRecord>.of(initial);

  final Completer<void> writeStarted = Completer<void>();
  final Completer<void> releaseWrite = Completer<void>();
  List<NoteRecord> records;

  @override
  Future<List<NoteRecord>> readNotes() async {
    return List<NoteRecord>.of(records);
  }

  @override
  Future<void> writeNotes(Iterable<NoteRecord> notes) async {
    records = List<NoteRecord>.of(notes);
    if (!writeStarted.isCompleted) {
      writeStarted.complete();
    }
    await releaseWrite.future;
  }
}

void main() {
  group('NoteRepository CRUD', () {
    test('round-trips a Note through the native file context', () async {
      final Directory supportDirectory = await Directory.systemTemp.createTemp(
        'note_repository_integration_test_',
      );
      try {
        final NoteRepository repository = NoteRepository(
          databaseContext: FileDatabaseContext(
            applicationSupportPathResolver: () async => supportDirectory.path,
          ),
        );
        final Note original = _note(
          id: 'note-file',
          title: 'Persisted note',
          content: 'Persisted body',
          minute: 1,
        );
        original.rename(
          'Persisted note, edited',
          DateTime.utc(2026, 9, 2, 10, 2),
        );

        await repository.save(original);
        final Note? restored = await repository.findById('note-file');

        expect(restored, isNotNull);
        expect(restored!.id, original.id);
        expect(restored.ownerId, original.ownerId);
        expect(restored.title, original.title);
        expect(restored.content, original.content);
        expect(restored.createdAt, original.createdAt);
        expect(restored.updatedAt, original.updatedAt);
      } finally {
        if (supportDirectory.existsSync()) {
          await supportDirectory.delete(recursive: true);
        }
      }
    });

    test('saves and reconstitutes domain Notes', () async {
      final _FakeDatabaseContext context = _FakeDatabaseContext();
      final NoteRepository repository = NoteRepository(
        databaseContext: context,
      );
      final Note original = _note(
        id: 'note-1',
        ownerId: 'owner-1',
        title: 'A note',
        content: 'Body',
        minute: 1,
      );

      await repository.save(original);
      final Note? restored = await repository.findById('note-1');

      expect(restored, isNotNull);
      expect(restored!.id, original.id);
      expect(restored.ownerId, original.ownerId);
      expect(restored.title, original.title);
      expect(restored.content, original.content);
      expect(restored.createdAt, original.createdAt);
      expect(restored.updatedAt, original.updatedAt);
      expect(
        context.records.single.toJson(),
        NoteMapper.toRecord(original).toJson(),
      );
    });

    test('upserts by id while preserving insertion order', () async {
      final _FakeDatabaseContext context = _FakeDatabaseContext();
      final NoteRepository repository = NoteRepository(
        databaseContext: context,
      );

      await repository.save(_note(id: 'note-1', title: 'First', minute: 1));
      await repository.save(_note(id: 'note-2', title: 'Second', minute: 2));
      await repository.save(
        _note(id: 'note-1', title: 'Updated first', minute: 3),
      );

      final List<Note> notes = await repository.findByOwnerId('owner-1');
      expect(notes.map((Note note) => note.id), ['note-1', 'note-2']);
      expect(notes.first.title, 'Updated first');
      expect(context.records.map((NoteRecord record) => record.id), [
        'note-1',
        'note-2',
      ]);
    });

    test('filters by owner and returns an empty list when absent', () async {
      final NoteRepository repository = NoteRepository(
        databaseContext: _FakeDatabaseContext(),
      );

      await repository.save(_note(id: 'mine', ownerId: 'owner-1'));
      await repository.save(_note(id: 'theirs', ownerId: 'owner-2'));

      final List<Note> mine = await repository.findByOwnerId('owner-1');
      expect(mine.map((Note note) => note.id), ['mine']);
      expect(await repository.findByOwnerId('missing'), isEmpty);
    });

    test('deleteById is idempotent', () async {
      final NoteRepository repository = NoteRepository(
        databaseContext: _FakeDatabaseContext(),
      );

      await repository.save(_note(id: 'note-1'));
      await repository.deleteById('missing');
      await repository.deleteById('note-1');
      await repository.deleteById('note-1');

      expect(await repository.findById('note-1'), isNull);
    });

    test('factory allows a context override and returns the repository', () {
      final domain.INoteRepository repository = createNoteRepository(
        databaseContext: _FakeDatabaseContext(),
      );

      expect(repository, isA<NoteRepository>());
    });
  });

  group('NoteRepository operation ordering', () {
    test('serializes concurrent mutations without losing an update', () async {
      final _FakeDatabaseContext context = _FakeDatabaseContext();
      final NoteRepository repository = NoteRepository(
        databaseContext: context,
      );

      await Future.wait(<Future<void>>[
        repository.save(_note(id: 'note-1', minute: 1)),
        repository.save(_note(id: 'note-2', minute: 2)),
      ]);

      expect(context.records.map((NoteRecord record) => record.id), [
        'note-1',
        'note-2',
      ]);
      expect(context.maximumActiveOperations, 1);
    });

    test('a read waits until a preceding mutation has committed', () async {
      final _BlockingWriteContext context = _BlockingWriteContext();
      final NoteRepository repository = NoteRepository(
        databaseContext: context,
      );
      final Future<void> save = repository.save(_note(id: 'note-1'));

      await context.writeStarted.future;
      bool readCompleted = false;
      final Future<Note?> read = repository.findById('note-1').then((
        Note? note,
      ) {
        readCompleted = true;
        return note;
      });
      await Future<void>.delayed(Duration.zero);
      expect(readCompleted, isFalse);

      context.releaseWrite.complete();
      await save;
      expect(await read, isNotNull);
    });
  });
}
