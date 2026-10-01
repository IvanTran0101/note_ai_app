import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/current_user.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/note_intelligence/summary_cloud_consent.dart';
import 'package:note_ai_app/application/note_intelligence/summary_run_context.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/domain/note_intelligence/summary.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/domain/notes/note_repository.dart';

final DateTime _createdAt = DateTime.utc(2026, 9, 3, 10);

final class _FakeCurrentUser implements ICurrentUser, SessionGenerationSource {
  _FakeCurrentUser(this.identity);

  @override
  AuthIdentity? identity;

  @override
  int sessionGeneration = 0;

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
  void Function()? beforeFindById;
  Object? findByIdError;
  Object? findByOwnerIdError;
  Object? saveError;
  Object? deleteError;

  @override
  Future<Note?> findById(String id) async {
    findByIdCalls++;
    beforeFindById?.call();
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
  SummarizeNoteRun? summarizeRun,
  SummaryCloudConsent? cloudConsent,
  SessionGenerationReader? sessionGeneration,
}) {
  return NoteApplicationService(
    noteRepository: repository,
    currentUser: currentUser ?? _authenticatedUser(),
    generateId: generateId,
    now: now,
    summarizeContent: summarizeContent,
    summarizeRun: summarizeRun,
    cloudConsent: cloudConsent,
    sessionGeneration: sessionGeneration,
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

  group('NoteApplicationService.summarizeNote run context', () {
    test('dispatches the selected snapshot with captured facts', () async {
      final Note saved = _note(
        ownerId: 'user-a',
        title: 'Selected title',
        content: 'Selected body',
      );
      final _FakeNoteRepository repository = _FakeNoteRepository(
        initial: <Note>[saved],
      );
      final _FakeCurrentUser currentUser = _authenticatedUser('user-a')
        ..sessionGeneration = 4;
      final SummaryRunScope scope = SummaryRunScope();
      final SummaryCloudConsent consent = SummaryCloudConsent()
        ..grant(accountUserId: 'user-a', sessionGeneration: 4);
      final NoteDto selected = NoteDto.fromDomain(saved);
      SummaryRunContext? seen;

      final Summary result = await _service(
        repository,
        currentUser: currentUser,
        cloudConsent: consent,
        summarizeRun: (SummaryRunContext context) async {
          seen = context;
          return const Summary('Generated summary');
        },
      ).summarizeNote(saved.id, selectedSnapshot: selected, scope: scope);

      expect(result, const Summary('Generated summary'));
      final SummaryRunContext context = seen!;
      expect(context.noteSnapshot, same(selected));
      expect(context.noteSnapshot, NoteDto.fromDomain(saved));
      expect(context.accountUserId, 'user-a');
      expect(context.sessionGeneration, 4);
      expect(context.scope, same(scope));
      expect(context.consent.accountUserId, 'user-a');
      expect(context.consent.sessionGeneration, 4);
      expect(context.consent.isGranted, isTrue);
      expect(context.consent.consentGeneration, greaterThan(0));
      expect(consent.isCurrent(context.consent), isTrue);
      // The captured snapshot is immutable, so the run cannot rewrite it.
      expect(selected, NoteDto.fromDomain(saved));
      expect(repository.savedNotes, isEmpty);
    });

    test('captures the saved revision when the UI selected nothing', () async {
      final Note saved = _note(title: 'Saved title', content: 'Saved body');
      final _FakeNoteRepository repository = _FakeNoteRepository(
        initial: <Note>[saved],
      );
      SummaryRunContext? seen;

      await _service(
        repository,
        summarizeRun: (SummaryRunContext context) async {
          seen = context;
          return const Summary('Generated summary');
        },
      ).summarizeNote(saved.id);

      expect(seen!.noteSnapshot, NoteDto.fromDomain(saved));
      expect(seen!.noteSnapshot.content, 'Saved body');
    });

    test('fails closed when the selected revision is not saved', () async {
      final Note saved = _note(content: 'Newer body');
      final NoteDto stale = NoteDto.fromDomain(_note(content: 'Older body'));
      bool dispatched = false;

      await expectLater(
        _service(
          _FakeNoteRepository(initial: <Note>[saved]),
          summarizeRun: (SummaryRunContext context) async {
            dispatched = true;
            return const Summary('Generated summary');
          },
        ).summarizeNote(saved.id, selectedSnapshot: stale),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.noteChanged)),
      );
      expect(dispatched, isFalse);
    });

    test('rejects a mismatched or foreign snapshot before reading', () async {
      final _FakeNoteRepository repository = _FakeNoteRepository(
        initial: <Note>[_note()],
      );
      final NoteApplicationService service = _service(
        repository,
        currentUser: _authenticatedUser('user-a'),
        summarizeRun: (SummaryRunContext context) async =>
            const Summary('Generated summary'),
      );
      final NoteDto foreign = NoteDto.fromDomain(
        _note(ownerId: 'user-b', content: 'Foreign body'),
      );

      await expectLater(
        service.summarizeNote(
          'other-id',
          selectedSnapshot: NoteDto.fromDomain(_note()),
        ),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.noteChanged)),
      );
      await expectLater(
        service.summarizeNote('note-1', selectedSnapshot: foreign),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.noteChanged)),
      );
      expect(repository.findByIdCalls, 0);
    });

    test('reports a missing note as a typed failure on the run path', () async {
      await expectLater(
        _service(
          _FakeNoteRepository(),
          summarizeRun: (SummaryRunContext context) async =>
              const Summary('Generated summary'),
        ).summarizeNote('missing', scope: SummaryRunScope()),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.noteNotFound)),
      );
    });

    test('reports a foreign note as missing on the run path', () async {
      final _FakeNoteRepository repository = _FakeNoteRepository(
        initial: <Note>[_note(ownerId: 'other-user')],
      );

      await expectLater(
        _service(
          repository,
          summarizeRun: (SummaryRunContext context) async =>
              const Summary('Generated summary'),
        ).summarizeNote('note-1'),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.noteNotFound)),
      );
    });

    test('captures a not-granted consent when no store is wired', () async {
      SummaryRunContext? seen;

      await _service(
        _FakeNoteRepository(initial: <Note>[_note()]),
        summarizeRun: (SummaryRunContext context) async {
          seen = context;
          return const Summary('Generated summary');
        },
      ).summarizeNote('note-1');

      expect(seen!.consent.isGranted, isFalse);
      expect(seen!.consent.consentGeneration, 0);
    });

    test(
      'discards the result when the account switches during the read',
      () async {
        final Note saved = _note();
        final _FakeCurrentUser currentUser = _authenticatedUser('user-a')
          ..sessionGeneration = 2;
        bool dispatched = false;
        final _FakeNoteRepository repository =
            _FakeNoteRepository(initial: <Note>[saved])
              ..beforeFindById = () {
                currentUser.identity = AuthIdentity(
                  userId: 'user-b',
                  email: 'user-b@example.test',
                  isEmailVerified: true,
                );
                currentUser.sessionGeneration = 3;
              };

        await expectLater(
          _service(
            repository,
            currentUser: currentUser,
            summarizeRun: (SummaryRunContext context) async {
              dispatched = true;
              return const Summary('Generated summary');
            },
          ).summarizeNote(saved.id, scope: SummaryRunScope()),
          throwsA(
            const SummaryRunFailure(SummaryRunFailureCode.sessionChanged),
          ),
        );
        expect(dispatched, isFalse);
      },
    );

    test('discards the result when the generation moves on mid-run', () async {
      final Note saved = _note(ownerId: 'user-a');
      final _FakeCurrentUser currentUser = _authenticatedUser('user-a')
        ..sessionGeneration = 1;
      final SummaryCloudConsent consent = SummaryCloudConsent()
        ..grant(accountUserId: 'user-a', sessionGeneration: 1);

      await expectLater(
        _service(
          _FakeNoteRepository(initial: <Note>[saved]),
          currentUser: currentUser,
          cloudConsent: consent,
          summarizeRun: (SummaryRunContext context) async {
            // Same account, new session: a sign-out and sign-in must not let a
            // result captured before the transition reach the UI.
            currentUser.sessionGeneration = 2;
            return const Summary('Stale summary');
          },
        ).summarizeNote(saved.id, scope: SummaryRunScope()),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.sessionChanged)),
      );
    });

    test('discards the result when the scope is cancelled mid-run', () async {
      final Note saved = _note();
      final SummaryRunScope scope = SummaryRunScope();

      await expectLater(
        _service(
          _FakeNoteRepository(initial: <Note>[saved]),
          summarizeRun: (SummaryRunContext context) async {
            scope.cancel();
            return const Summary('Discarded summary');
          },
        ).summarizeNote(saved.id, scope: scope),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.cancelled)),
      );
      expect(scope.cancelReason, SummaryRunFailureCode.cancelled);
    });

    test('keeps the first cancellation reason from a mid-run cancel', () async {
      final Note saved = _note();
      final SummaryRunScope scope = SummaryRunScope();

      await expectLater(
        _service(
          _FakeNoteRepository(initial: <Note>[saved]),
          summarizeRun: (SummaryRunContext context) async {
            scope.cancel(reason: SummaryRunFailureCode.conflict);
            scope.cancel(reason: SummaryRunFailureCode.deadlineExceeded);
            return const Summary('Discarded summary');
          },
        ).summarizeNote(saved.id, scope: scope),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.conflict)),
      );
    });

    test('never starts a run whose scope is already cancelled', () async {
      final _FakeNoteRepository repository = _FakeNoteRepository(
        initial: <Note>[_note()],
      );
      bool dispatched = false;
      final SummaryRunScope scope = SummaryRunScope()
        ..cancel(reason: SummaryRunFailureCode.conflict);

      await expectLater(
        _service(
          repository,
          summarizeRun: (SummaryRunContext context) async {
            dispatched = true;
            return const Summary('Generated summary');
          },
        ).summarizeNote('note-1', scope: scope),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.conflict)),
      );
      expect(dispatched, isFalse);
      expect(repository.findByIdCalls, 0);
    });

    test('discards the result when the saved revision changes mid-run', () async {
      final Note saved = _note(content: 'First body');
      final _FakeNoteRepository repository = _FakeNoteRepository(
        initial: <Note>[saved],
      );

      await expectLater(
        _service(
          repository,
          summarizeRun: (SummaryRunContext context) async {
            // The draft was edited without cancelling the scope: the persisted
            // revision no longer matches what this run summarized.
            repository.notes[saved.id] = _note(content: 'Second body');
            return const Summary('Discarded summary');
          },
        ).summarizeNote(saved.id, selectedSnapshot: NoteDto.fromDomain(saved)),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.noteChanged)),
      );
    });

    test('discards the result when consent is revoked mid-run', () async {
      final Note saved = _note();
      final SummaryCloudConsent consent = SummaryCloudConsent()
        ..grant(accountUserId: 'local-user', sessionGeneration: 0);

      await expectLater(
        _service(
          _FakeNoteRepository(initial: <Note>[saved]),
          cloudConsent: consent,
          summarizeRun: (SummaryRunContext context) async {
            consent.revoke();
            return const Summary('Discarded summary');
          },
        ).summarizeNote(saved.id, scope: SummaryRunScope()),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.consentRequired)),
      );
    });

    test('rechecks consent after the final saved-revision read', () async {
      final Note saved = _note();
      final _FakeNoteRepository repository = _FakeNoteRepository(
        initial: <Note>[saved],
      );
      final _FakeCurrentUser currentUser = _authenticatedUser();
      final SummaryCloudConsent consent = SummaryCloudConsent()
        ..grant(
          accountUserId: currentUser.requiredUserId,
          sessionGeneration: currentUser.sessionGeneration,
        );
      repository.beforeFindById = () {
        if (repository.findByIdCalls == 2) {
          consent.revoke(accountUserId: currentUser.requiredUserId);
        }
      };

      await expectLater(
        _service(
          repository,
          currentUser: currentUser,
          cloudConsent: consent,
          summarizeRun: (SummaryRunContext context) async =>
              const Summary('discarded summary'),
        ).summarizeNote(
          saved.id,
          selectedSnapshot: NoteDto.fromDomain(saved),
          scope: SummaryRunScope(),
        ),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.consentRequired)),
      );
      expect(repository.findByIdCalls, 2);
    });

    test('reads the injected session generation reader first', () async {
      final Note saved = _note(ownerId: 'user-a');
      final _FakeCurrentUser currentUser = _authenticatedUser('user-a')
        ..sessionGeneration = 1;
      SummaryRunContext? seen;

      await _service(
        _FakeNoteRepository(initial: <Note>[saved]),
        currentUser: currentUser,
        sessionGeneration: () => 9,
        summarizeRun: (SummaryRunContext context) async {
          seen = context;
          return const Summary('Generated summary');
        },
      ).summarizeNote(saved.id);

      expect(seen!.sessionGeneration, 9);
      expect(currentUser.sessionGeneration, 1);
    });

    test('stops an injected reader that moves mid-run', () async {
      final Note saved = _note();
      int generation = 9;

      await expectLater(
        _service(
          _FakeNoteRepository(initial: <Note>[saved]),
          sessionGeneration: () => generation,
          summarizeRun: (SummaryRunContext context) async {
            generation = 10;
            return const Summary('Stale summary');
          },
        ).summarizeNote(saved.id, scope: SummaryRunScope()),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.sessionChanged)),
      );
    });
  });

  group('NoteApplicationService.summarizeNote local path', () {
    test('keeps the local callback and never re-reads the revision', () async {
      final Note saved = _note(content: 'Local body');
      final _FakeNoteRepository repository = _FakeNoteRepository(
        initial: <Note>[saved],
      );
      final SummaryRunScope scope = SummaryRunScope();
      String? receivedContent;

      final Summary result =
          await _service(
            repository,
            summarizeContent: (String content) async {
              receivedContent = content;
              return const Summary('Local summary');
            },
          ).summarizeNote(
            saved.id,
            selectedSnapshot: NoteDto.fromDomain(saved),
            scope: scope,
          );

      expect(result, const Summary('Local summary'));
      expect(receivedContent, 'Local body');
      expect(repository.findByIdCalls, 1);
      expect(repository.savedNotes, isEmpty);
      expect(scope.isCancelled, isFalse);
    });

    test('still dispatches a run when a dispatcher is wired', () async {
      final Note saved = _note(content: 'Local body');
      bool localCalled = false;
      bool dispatched = false;

      await _service(
        _FakeNoteRepository(initial: <Note>[saved]),
        summarizeContent: (String content) async {
          localCalled = true;
          return const Summary('Local summary');
        },
        summarizeRun: (SummaryRunContext context) async {
          dispatched = true;
          return const Summary('Dispatched summary');
        },
      ).summarizeNote(saved.id, scope: SummaryRunScope());

      expect(dispatched, isTrue);
      expect(localCalled, isFalse);
    });

    test('cancels a local run through its scope', () async {
      final Note saved = _note();
      final SummaryRunScope scope = SummaryRunScope();

      await expectLater(
        _service(
          _FakeNoteRepository(initial: <Note>[saved]),
          summarizeContent: (String content) async {
            scope.cancel(reason: SummaryRunFailureCode.noteChanged);
            return const Summary('Discarded summary');
          },
        ).summarizeNote(saved.id, scope: scope),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.noteChanged)),
      );
    });

    test('does not return a local result after a session change', () async {
      final Note saved = _note();
      final _FakeCurrentUser currentUser = _authenticatedUser('local-user');

      await expectLater(
        _service(
          _FakeNoteRepository(initial: <Note>[saved]),
          currentUser: currentUser,
          summarizeContent: (String content) async {
            currentUser.sessionGeneration = 1;
            return const Summary('Stale summary');
          },
        ).summarizeNote(saved.id),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.sessionChanged)),
      );
    });
  });
}
