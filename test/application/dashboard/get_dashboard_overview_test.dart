import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/dashboard/dashboard_overview.dart';
import 'package:note_ai_app/application/dashboard/get_dashboard_overview.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/domain/notes/note_repository.dart';

final DateTime _baseTime = DateTime.utc(2026, 9, 10, 9);

void main() {
  group('GetDashboardOverview', () {
    test('projects the owner notes ordered by most recently updated', () async {
      final _FakeNoteRepository repository = _FakeNoteRepository(<Note>[
        _note(id: 'older', updatedAt: _baseTime),
        _note(id: 'newer', updatedAt: _baseTime.add(const Duration(hours: 2))),
        _note(
          id: 'other-owner',
          ownerId: 'other-user',
          updatedAt: _baseTime.add(const Duration(hours: 3)),
        ),
        _note(id: 'middle', updatedAt: _baseTime.add(const Duration(hours: 1))),
      ]);
      final GetDashboardOverview ownerQuery = GetDashboardOverview(
        noteRepository: repository,
        ownerId: 'local-user',
      );

      final DashboardOverview overview = await ownerQuery.execute(
        recentLimit: 2,
      );

      expect(repository.lastOwnerId, 'local-user');
      expect(overview.totalNotes, 3);
      expect(overview.recentNotes.map((note) => note.id), <String>[
        'newer',
        'middle',
      ]);
      expect(overview.lastUpdatedAt, _baseTime.add(const Duration(hours: 2)));
    });

    test('uses the note id as a deterministic tie-breaker', () async {
      final _FakeNoteRepository repository = _FakeNoteRepository(<Note>[
        _note(id: 'z-note', updatedAt: _baseTime),
        _note(id: 'a-note', updatedAt: _baseTime),
      ]);
      final DashboardOverview overview = await GetDashboardOverview(
        noteRepository: repository,
        ownerId: 'local-user',
      ).execute(recentLimit: 5);

      expect(overview.recentNotes.map((note) => note.id), <String>[
        'a-note',
        'z-note',
      ]);
    });

    test(
      'returns an immutable empty projection when the owner has no notes',
      () async {
        final DashboardOverview overview = await GetDashboardOverview(
          noteRepository: _FakeNoteRepository(const <Note>[]),
          ownerId: 'local-user',
        ).execute(recentLimit: 5);

        expect(overview.isEmpty, isTrue);
        expect(overview.totalNotes, 0);
        expect(overview.recentNotes, isEmpty);
        expect(overview.lastUpdatedAt, isNull);
        expect(
          () => overview.recentNotes.add(NoteDto.fromDomain(_note())),
          throwsUnsupportedError,
        );
      },
    );

    test(
      'rejects a non-positive recent limit before reading the repository',
      () async {
        final _FakeNoteRepository repository = _FakeNoteRepository(
          const <Note>[],
        );
        final GetDashboardOverview query = GetDashboardOverview(
          noteRepository: repository,
          ownerId: 'local-user',
        );

        await expectLater(
          query.execute(recentLimit: 0),
          throwsA(isA<ArgumentError>()),
        );
        expect(repository.findByOwnerIdCalls, 0);
      },
    );

    test('preserves repository failures', () async {
      final StateError error = StateError('read failed');
      final _FakeNoteRepository repository = _FakeNoteRepository(const <Note>[])
        ..findByOwnerIdError = error;

      await expectLater(
        GetDashboardOverview(
          noteRepository: repository,
          ownerId: 'local-user',
        ).execute(recentLimit: 5),
        throwsA(same(error)),
      );
    });
  });
}

Note _note({
  String id = 'note-1',
  String ownerId = 'local-user',
  DateTime? updatedAt,
}) {
  final DateTime createdAt = _baseTime;
  return Note.reconstitute(
    id: id,
    ownerId: ownerId,
    title: id,
    content: 'Content for $id',
    createdAt: createdAt,
    updatedAt: updatedAt ?? createdAt,
  );
}

final class _FakeNoteRepository implements INoteRepository {
  _FakeNoteRepository(Iterable<Note> notes)
    : _notes = List<Note>.unmodifiable(notes),
      lastOwnerId = null;

  final List<Note> _notes;
  String? lastOwnerId;
  int findByOwnerIdCalls = 0;
  Object? findByOwnerIdError;

  @override
  Future<Note?> findById(String id) async => throw UnimplementedError();

  @override
  Future<List<Note>> findByOwnerId(String ownerId) async {
    findByOwnerIdCalls++;
    lastOwnerId = ownerId;
    final Object? error = findByOwnerIdError;
    if (error != null) {
      throw error;
    }
    return _notes
        .where((note) => note.ownerId == ownerId)
        .toList(growable: false);
  }

  @override
  Future<void> save(Note note) async => throw UnimplementedError();

  @override
  Future<void> deleteById(String id) async => throw UnimplementedError();
}
