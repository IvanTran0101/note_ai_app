import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/note_intelligence/summary_run_context.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/note_intelligence/summary.dart';
import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/domain/notes/note_repository.dart';

final DateTime _time = DateTime.utc(2026, 10, 1);
Note _note([String body = 'Synthetic body']) => Note.reconstitute(
  id: 'note-a',
  ownerId: 'account-a',
  title: 'Synthetic note',
  content: body,
  createdAt: _time,
  updatedAt: _time,
);

final class _Repo implements INoteRepository {
  Note? note = _note();
  int reads = 0;
  void Function()? onRead;
  @override
  Future<Note?> findById(String id) async {
    reads++;
    onRead?.call();
    return note;
  }

  @override
  Future<List<Note>> findByOwnerId(String ownerId) async =>
      note == null ? <Note>[] : <Note>[note!];

  @override
  Future<Note> updateById({
    required String noteId,
    required String ownerId,
    required String expectedAccountUserId,
    required NoteChange change,
    required NoteCommitFence canCommit,
  }) async => throw StateError('must not edit');
  @override
  Future<void> save(Note note) async => throw StateError('must not write');
  @override
  Future<void> deleteById(String id) async =>
      throw StateError('must not delete');
}

void main() {
  late _Repo repo;
  late CurrentUserSession session;
  setUp(() {
    repo = _Repo();
    session = CurrentUserSession()
      ..setIdentity(
        AuthIdentity(
          userId: 'account-a',
          email: 'a@example.test',
          isEmailVerified: true,
        ),
      );
  });
  NoteApplicationService service(SummarizeNoteContent generate) =>
      NoteApplicationService(
        noteRepository: repo,
        currentUser: session,
        generateId: () => 'unused',
        now: () => _time,
        summarizeContent: generate,
      );

  test(
    'scoped local output is discarded after an external saved edit',
    () async {
      final NoteDto selected = NoteDto.fromDomain(repo.note!);
      await expectLater(
        service((_) async {
          repo.note = _note('Externally edited body');
          return const Summary('Stale local output');
        }).summarizeNote(
          'note-a',
          selectedSnapshot: selected,
          scope: SummaryRunScope(),
        ),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.noteChanged)),
      );
      expect(repo.reads, 2);
      expect(repo.note!.content, 'Externally edited body');
    },
  );
  test('scoped local output is discarded after deletion', () async {
    await expectLater(
      service((_) async {
        repo.note = null;
        return const Summary('Deleted output');
      }).summarizeNote('note-a', scope: SummaryRunScope()),
      throwsA(const SummaryRunFailure(SummaryRunFailureCode.noteNotFound)),
    );
  });
  test(
    'a session change during the final local read invalidates output',
    () async {
      repo.onRead = () {
        if (repo.reads == 2) session.clear();
      };
      await expectLater(
        service((_) async => const Summary('Stale output'))
            .summarizeNote('note-a', scope: SummaryRunScope()),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.sessionChanged)),
      );
    },
  );
  test('legacy unscoped local calls keep the original read count', () async {
    expect(
      await service((_) async => const Summary('Legacy output'))
          .summarizeNote('note-a'),
      const Summary('Legacy output'),
    );
    expect(repo.reads, 1);
  });
}
