import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/current_user.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/domain/note_intelligence/summary.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/domain/notes/note_repository.dart';

final DateTime _createdAt = DateTime.utc(2026, 9, 3, 10);

final class _FakeCurrentUser implements ICurrentUser {
  _FakeCurrentUser(this.identity);

  @override
  AuthIdentity? identity;

  @override
  bool get isAuthenticated => identity != null;

  @override
  String? get userId => identity?.userId;

  @override
  String get requiredUserId {
    final String? currentUserId = userId;
    if (currentUserId == null) {
      throw const UnauthenticatedException();
    }
    return currentUserId;
  }
}

final class _FakeNoteRepository implements INoteRepository {
  _FakeNoteRepository({Iterable<Note> initial = const <Note>[]})
    : notes = <String, Note>{for (final Note note in initial) note.id: note};

  final Map<String, Note> notes;
  final List<Note> savedNotes = <Note>[];
  final List<String> deletedIds = <String>[];
  int findByIdCalls = 0;
  int findByOwnerIdCalls = 0;
  Object? findByIdError;
  Object? findByOwnerIdError;
  Object? saveError;
  Object? deleteError;

  @override
  Future<Note?> findById(String id) async {
    findByIdCalls++;
    final Object? error = findByIdError;
    if (error != null) {
      throw error;
    }
    return notes[id];
  }

  @override
  Future<List<Note>> findByOwnerId(String ownerId) async {
    findByOwnerIdCalls++;
    final Object? error = findByOwnerIdError;
    if (error != null) {
      throw error;
    }
    return notes.values
        .where((Note note) => note.ownerId == ownerId)
        .toList(growable: false);
  }

  @override
  Future<void> save(Note note) async {
    final Object? error = saveError;
    if (error != null) {
      throw error;
    }
    savedNotes.add(note);
    notes[note.id] = note;
  }

  @override
  Future<void> deleteById(String id) async {
    final Object? error = deleteError;
    if (error != null) {
      throw error;
    }
    deletedIds.add(id);
    notes.remove(id);
  }
}

Note _note({
  String id = 'note-1',
  String ownerId = 'local-user',
  String title = 'Title',
  String content = 'Content',
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final DateTime created = createdAt ?? _createdAt;
  return Note.reconstitute(
    id: id,
    ownerId: ownerId,
    title: title,
    content: content,
    createdAt: created,
    updatedAt: updatedAt ?? created,
  );
}

NoteApplicationService _service(
  _FakeNoteRepository repository, {
  _FakeCurrentUser? currentUser,
  NoteIdGenerator generateId = _defaultId,
  NoteClock now = _defaultNow,
  SummarizeNoteContent summarizeContent = _defaultSummary,
}) {
  return NoteApplicationService(
    noteRepository: repository,
    currentUser: currentUser ?? _authenticatedUser(),
    generateId: generateId,
    now: now,
    summarizeContent: summarizeContent,
  );
}

_FakeCurrentUser _authenticatedUser([String userId = 'local-user']) {
  return _FakeCurrentUser(
    AuthIdentity(
      userId: userId,
      email: '$userId@example.test',
      isEmailVerified: true,
    ),
  );
}

String _defaultId() => 'generated-note';

DateTime _defaultNow() => _createdAt;

Future<Summary> _defaultSummary(String content) async {
  return Summary('Summary of $content');
}

void main() {
  group('NoteDto', () {
    test('projects every field from the domain aggregate', () {
      final DateTime updatedAt = _createdAt.add(const Duration(hours: 1));
      final Note note = _note(updatedAt: updatedAt);

      final NoteDto dto = NoteDto.fromDomain(note);

      expect(dto, NoteDto.fromDomain(note));
      expect(dto.id, note.id);
      expect(dto.ownerId, note.ownerId);
      expect(dto.title, note.title);
      expect(dto.content, note.content);
      expect(dto.createdAt, note.createdAt);
      expect(dto.updatedAt, note.updatedAt);
      expect(dto.hashCode, NoteDto.fromDomain(note).hashCode);
    });
  });

  group('NoteApplicationService.listNotes', () {
    test(
      'returns immutable DTO projections for the configured owner',
      () async {
        final _FakeNoteRepository repository = _FakeNoteRepository(
          initial: <Note>[
            _note(id: 'mine-1'),
            _note(id: 'theirs', ownerId: 'other-user'),
            _note(id: 'mine-2', title: 'Second'),
          ],
        );
        final NoteApplicationService service = _service(repository);

        final List<NoteDto> notes = await service.listNotes();

        expect(notes, <NoteDto>[
          NoteDto.fromDomain(_note(id: 'mine-1')),
          NoteDto.fromDomain(_note(id: 'mine-2', title: 'Second')),
        ]);
        expect(repository.findByOwnerIdCalls, 1);
        expect(notes, hasLength(2));
        expect(() => notes.add(notes.first), throwsUnsupportedError);
      },
    );

    test('preserves repository errors', () async {
      final StateError error = StateError('read failed');
      final _FakeNoteRepository repository = _FakeNoteRepository()
        ..findByOwnerIdError = error;

      await expectLater(_service(repository).listNotes(), throwsA(same(error)));
    });

    test(
      'resolves the owner from the current user on every use case',
      () async {
        final _FakeNoteRepository repository = _FakeNoteRepository(
          initial: <Note>[
            _note(id: 'user-a-note', ownerId: 'user-a'),
            _note(id: 'user-b-note', ownerId: 'user-b'),
          ],
        );
        final _FakeCurrentUser currentUser = _authenticatedUser('user-a');
        final NoteApplicationService service = _service(
          repository,
          currentUser: currentUser,
        );

        expect((await service.listNotes()).map((note) => note.id), <String>[
          'user-a-note',
        ]);

        currentUser.identity = AuthIdentity(
          userId: 'user-b',
          email: 'user-b@example.test',
          isEmailVerified: true,
        );

        expect((await service.listNotes()).map((note) => note.id), <String>[
          'user-b-note',
        ]);
        final NoteDto created = await service.createNote(
          title: 'User B note',
          content: 'Content',
        );
        expect(created.ownerId, 'user-b');
      },
    );

    test(
      'rejects unauthenticated requests before repository side effects',
      () async {
        int generateIdCalls = 0;
        final _FakeNoteRepository repository = _FakeNoteRepository();
        final NoteApplicationService service = _service(
          repository,
          currentUser: _FakeCurrentUser(null),
          generateId: () {
            generateIdCalls++;
            return 'should-not-be-created';
          },
        );

        await expectLater(
          service.listNotes(),
          throwsA(isA<UnauthenticatedException>()),
        );
        await expectLater(
          service.createNote(title: 'Title', content: 'Content'),
          throwsA(isA<UnauthenticatedException>()),
        );
        await expectLater(
          service.deleteNote('note-1'),
          throwsA(isA<UnauthenticatedException>()),
        );

        expect(repository.findByOwnerIdCalls, 0);
        expect(repository.findByIdCalls, 0);
        expect(generateIdCalls, 0);
      },
    );
  });

  group('NoteApplicationService.createNote', () {
    test(
      'uses the generated id, owner, supplied fields, and UTC clock',
      () async {
        int idCalls = 0;
        int clockCalls = 0;
        final DateTime localTime = DateTime(2026, 9, 3, 17, 30);
        final _FakeNoteRepository repository = _FakeNoteRepository();
        final NoteApplicationService service = _service(
          repository,
          generateId: () {
            idCalls++;
            return 'created-note';
          },
          now: () {
            clockCalls++;
            return localTime;
          },
        );

        final NoteDto result = await service.createNote(
          title: 'A title',
          content: 'A body',
        );

        expect(idCalls, 1);
        expect(clockCalls, 1);
        expect(
          result,
          NoteDto(
            id: 'created-note',
            ownerId: 'local-user',
            title: 'A title',
            content: 'A body',
            createdAt: localTime.toUtc(),
            updatedAt: localTime.toUtc(),
          ),
        );
        expect(repository.savedNotes, hasLength(1));
        expect(repository.notes['created-note'], isNotNull);
      },
    );

    test('preserves repository save errors', () async {
      final StateError error = StateError('write failed');
      final _FakeNoteRepository repository = _FakeNoteRepository()
        ..saveError = error;

      await expectLater(
        _service(repository).createNote(title: 'Title', content: 'Content'),
        throwsA(same(error)),
      );
    });

    test('requests a sync only after the local save succeeds', () async {
      final _FakeNoteRepository repository = _FakeNoteRepository();
      final List<String> requestedAccounts = <String>[];
      final NoteApplicationService service = NoteApplicationService(
        noteRepository: repository,
        currentUser: _authenticatedUser('user-a'),
        generateId: _defaultId,
        now: _defaultNow,
        summarizeContent: _defaultSummary,
        requestSync: requestedAccounts.add,
      );

      await service.createNote(title: 'Title', content: 'Content');

      expect(requestedAccounts, <String>['user-a']);
      expect(repository.savedNotes, hasLength(1));
    });
  });

  group('NoteApplicationService.renameNote', () {
    test('mutates the aggregate and saves it with the new title', () async {
      final DateTime renamedAt = _createdAt.add(const Duration(hours: 2));
      final Note original = _note(content: 'Keep this body');
      final _FakeNoteRepository repository = _FakeNoteRepository(
        initial: <Note>[original],
      );

      final NoteDto result = await _service(
        repository,
        now: () => renamedAt,
      ).renameNote(noteId: original.id, title: 'Renamed');

      expect(result.title, 'Renamed');
      expect(result.content, original.content);
      expect(result.id, original.id);
      expect(result.ownerId, original.ownerId);
      expect(result.createdAt, original.createdAt);
      expect(result.updatedAt, renamedAt);
      expect(repository.savedNotes, contains(same(original)));
      expect(repository.notes[original.id]!.title, 'Renamed');
    });

    test('does not save when the note is missing', () async {
      final _FakeNoteRepository repository = _FakeNoteRepository();

      await expectLater(
        _service(repository).renameNote(noteId: 'missing', title: 'Renamed'),
        throwsA(isA<NoteNotFoundException>()),
      );
      expect(repository.savedNotes, isEmpty);
    });
  });

  group('NoteApplicationService.replaceContent', () {
    test('mutates the aggregate and saves the new content', () async {
      final DateTime replacedAt = _createdAt.add(const Duration(hours: 3));
      final Note original = _note(title: 'Keep this title');
      final _FakeNoteRepository repository = _FakeNoteRepository(
        initial: <Note>[original],
      );

      final NoteDto result = await _service(
        repository,
        now: () => replacedAt,
      ).replaceContent(noteId: original.id, content: 'Replaced body');

      expect(result.content, 'Replaced body');
      expect(result.title, original.title);
      expect(result.updatedAt, replacedAt);
      expect(repository.savedNotes, contains(same(original)));
    });

    test('preserves repository save errors', () async {
      final StateError error = StateError('write failed');
      final _FakeNoteRepository repository = _FakeNoteRepository(
        initial: <Note>[_note()],
      )..saveError = error;

      await expectLater(
        _service(repository)
            .replaceContent(noteId: 'note-1', content: 'New body'),
        throwsA(same(error)),
      );
    });
  });

  group('NoteApplicationService.deleteNote', () {
    test('deletes an owned note without saving it', () async {
      final _FakeNoteRepository repository = _FakeNoteRepository(
        initial: <Note>[_note()],
      );

      await _service(repository).deleteNote('note-1');

      expect(repository.deletedIds, <String>['note-1']);
      expect(repository.savedNotes, isEmpty);
      expect(repository.notes, isEmpty);
    });

    test('preserves repository delete errors', () async {
      final StateError error = StateError('delete failed');
      final _FakeNoteRepository repository = _FakeNoteRepository(
        initial: <Note>[_note()],
      )..deleteError = error;

      await expectLater(
        _service(repository).deleteNote('note-1'),
        throwsA(same(error)),
      );
    });
  });

  group('NoteApplicationService.summarizeNote', () {
    test(
      'summarizes content without mutating or saving the aggregate',
      () async {
        final Note original = _note(
          title: 'Original',
          content: 'Important body',
        );
        final _FakeNoteRepository repository = _FakeNoteRepository(
          initial: <Note>[original],
        );
        String? receivedContent;

        final Summary result = await _service(
          repository,
          summarizeContent: (String content) async {
            receivedContent = content;
            return const Summary('Generated summary');
          },
        ).summarizeNote(original.id);

        expect(result, const Summary('Generated summary'));
        expect(receivedContent, original.content);
        expect(repository.savedNotes, isEmpty);
        expect(original.title, 'Original');
        expect(original.content, 'Important body');
        expect(original.updatedAt, original.createdAt);
      },
    );

    test('preserves summarizer errors', () async {
      final StateError error = StateError('summary failed');
      final _FakeNoteRepository repository = _FakeNoteRepository(
        initial: <Note>[_note()],
      );

      await expectLater(
        _service(
          repository,
          summarizeContent: (String content) async => throw error,
        ).summarizeNote('note-1'),
        throwsA(same(error)),
      );
      expect(repository.savedNotes, isEmpty);
    });
  });

  group('NoteApplicationService access checks', () {
    test('throws NoteNotFoundException for every id-based operation', () async {
      final _FakeNoteRepository repository = _FakeNoteRepository();
      final NoteApplicationService service = _service(repository);

      await expectLater(
        service.renameNote(noteId: 'missing', title: 'New title'),
        throwsA(isA<NoteNotFoundException>()),
      );
      await expectLater(
        service.replaceContent(noteId: 'missing', content: 'New content'),
        throwsA(isA<NoteNotFoundException>()),
      );
      await expectLater(
        service.deleteNote('missing'),
        throwsA(isA<NoteNotFoundException>()),
      );
      await expectLater(
        service.summarizeNote('missing'),
        throwsA(isA<NoteNotFoundException>()),
      );
    });

    test(
      'throws NoteOwnershipException for every protected operation',
      () async {
        final Note foreignNote = _note(ownerId: 'other-user');
        final _FakeNoteRepository repository = _FakeNoteRepository(
          initial: <Note>[foreignNote],
        );
        final NoteApplicationService service = _service(repository);

        await expectLater(
          service.renameNote(noteId: foreignNote.id, title: 'New title'),
          throwsA(
            isA<NoteOwnershipException>().having(
              (NoteOwnershipException error) => error.actualOwnerId,
              'actualOwnerId',
              'other-user',
            ),
          ),
        );
        await expectLater(
          service.replaceContent(
            noteId: foreignNote.id,
            content: 'New content',
          ),
          throwsA(isA<NoteOwnershipException>()),
        );
        await expectLater(
          service.deleteNote(foreignNote.id),
          throwsA(isA<NoteOwnershipException>()),
        );
        await expectLater(
          service.summarizeNote(foreignNote.id),
          throwsA(isA<NoteOwnershipException>()),
        );

        expect(repository.savedNotes, isEmpty);
        expect(repository.deletedIds, isEmpty);
      },
    );
  });
}
