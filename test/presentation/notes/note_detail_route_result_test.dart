import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/presentation/notes/note_detail_route_result.dart';

void main() {
  final NoteDto note = NoteDto(
    id: 'note-1',
    ownerId: 'local-user',
    title: 'Title',
    content: 'Content',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  test('only saved and deleted results request a refresh', () {
    expect(
      const NoteDetailRouteResult(reason: NoteDetailExitReason.saved)
          .shouldRefresh,
      isTrue,
    );
    expect(
      const NoteDetailRouteResult(reason: NoteDetailExitReason.deleted)
          .shouldRefresh,
      isTrue,
    );
    expect(
      const NoteDetailRouteResult(reason: NoteDetailExitReason.discarded)
          .shouldRefresh,
      isFalse,
    );
    expect(
      const NoteDetailRouteResult(reason: NoteDetailExitReason.cancelled)
          .shouldRefresh,
      isFalse,
    );
  });

  test('saved result carries the updated note and has value semantics', () {
    const NoteDetailRouteResult first = NoteDetailRouteResult(
      reason: NoteDetailExitReason.saved,
      note: null,
    );
    final NoteDetailRouteResult withNote = NoteDetailRouteResult(
      reason: NoteDetailExitReason.saved,
      note: note,
    );
    final NoteDetailRouteResult equal = NoteDetailRouteResult(
      reason: NoteDetailExitReason.saved,
      note: note,
    );

    expect(first.note, isNull);
    expect(withNote.note, note);
    expect(withNote, equal);
    expect(withNote.hashCode, equal.hashCode);
    expect(withNote.toString(), contains('saved'));
  });

  test('non-saved results do not carry a note payload', () {
    expect(
      () => NoteDetailRouteResult(
        reason: NoteDetailExitReason.deleted,
        note: note,
      ),
      throwsAssertionError,
    );
  });
}
