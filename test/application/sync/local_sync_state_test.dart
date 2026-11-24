import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/note_sync_status.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_conflict.dart';
import 'package:note_ai_app/application/sync/sync_cursor.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';

final DateTime _createdAt = DateTime.utc(2026, 9, 25, 9);
final DateTime _updatedAt = DateTime.utc(2026, 9, 25, 10);
const SyncNotePayload _payload = SyncNotePayload(title: 'T', content: 'C');

LocalNoteState _note({
  String id = 'note-1',
  String ownerId = 'user-1',
  NoteSyncStatus status = NoteSyncStatus.synced,
}) {
  return LocalNoteState(
    id: id,
    ownerId: ownerId,
    title: 'Title',
    content: 'Content',
    createdAt: _createdAt,
    updatedAt: _updatedAt,
    status: status,
  );
}

PendingMutation _pending({
  String mutationId = 'm-1',
  String noteId = 'note-1',
}) {
  return PendingMutation(
    mutationId: mutationId,
    noteId: noteId,
    operation: SyncMutationOperation.create,
    baseRevision: 0,
    payload: _payload,
    createdAt: _updatedAt,
  );
}

SyncConflict _conflict({String noteId = 'note-1'}) {
  return SyncConflict(
    noteId: noteId,
    remote: SyncNoteSnapshot(
      id: noteId,
      title: 'Remote',
      content: 'Remote',
      createdAt: _createdAt,
      serverUpdatedAt: _updatedAt,
      revision: 2,
    ),
    local: _note(id: noteId),
    pending: _pending(noteId: noteId),
    detectedAt: _updatedAt,
  );
}

void main() {
  test('an account with nothing stored is an empty, cursorless state', () {
    final LocalSyncState state = LocalSyncState(accountUserId: 'user-1');

    expect(state.isEmpty, isTrue);
    expect(state.cursor, isNull);
    expect(state.notes, isEmpty);
    expect(state.outbox, isEmpty);
    expect(state.conflicts, isEmpty);
    expect(() => LocalSyncState(accountUserId: ' '), throwsArgumentError);
  });

  test('rejects duplicate note ids and duplicate mutation ids', () {
    expect(
      () => LocalSyncState(
        accountUserId: 'user-1',
        notes: <LocalNoteState>[_note(), _note()],
      ),
      throwsArgumentError,
    );
    expect(
      () => LocalSyncState(
        accountUserId: 'user-1',
        notes: <LocalNoteState>[
          _note(),
          _note(id: 'note-2'),
        ],
        outbox: <PendingMutation>[_pending(), _pending()],
      ),
      throwsArgumentError,
    );
    expect(
      () => LocalSyncState(
        accountUserId: 'user-1',
        outbox: <PendingMutation>[
          _pending(),
          _pending(mutationId: 'm-2'),
        ],
      ),
      returnsNormally,
    );
  });

  test('keeps the store account-isolated', () {
    expect(
      () => LocalSyncState(
        accountUserId: 'user-1',
        notes: <LocalNoteState>[_note(ownerId: 'user-2')],
      ),
      throwsArgumentError,
    );
    expect(
      LocalSyncState(
        accountUserId: 'user-2',
        notes: <LocalNoteState>[_note(ownerId: 'user-2')],
      ).notes,
      hasLength(1),
    );
  });

  test('copies collections so an accepted state cannot change later', () {
    final List<LocalNoteState> sourceNotes = <LocalNoteState>[_note()];
    final List<PendingMutation> sourceOutbox = <PendingMutation>[_pending()];
    final List<SyncConflict> sourceConflicts = <SyncConflict>[_conflict()];
    final LocalSyncState state = LocalSyncState(
      accountUserId: 'user-1',
      notes: sourceNotes,
      outbox: sourceOutbox,
      conflicts: sourceConflicts,
    );

    sourceNotes.clear();
    sourceOutbox.clear();
    sourceConflicts.clear();

    expect(state.notes, hasLength(1));
    expect(state.outbox, hasLength(1));
    expect(state.conflicts, hasLength(1));
    expect(() => state.notes.add(_note(id: 'note-2')), throwsUnsupportedError);
    expect(
      () => state.outbox.add(_pending(mutationId: 'm-2')),
      throwsUnsupportedError,
    );
    expect(() => state.conflicts.clear(), throwsUnsupportedError);
  });

  test('carries the opaque cursor unchanged', () {
    const SyncCursor cursor = SyncCursor('  opaque:7  ');
    final LocalSyncState state = LocalSyncState(
      accountUserId: 'user-1',
      cursor: cursor,
    );

    expect(state.cursor?.value, '  opaque:7  ');
    expect(state, isNot(LocalSyncState(accountUserId: 'user-1')));
    expect(state, LocalSyncState(accountUserId: 'user-1', cursor: cursor));
  });

  test('compares equal content across distinct list instances', () {
    final LocalSyncState first = LocalSyncState(
      accountUserId: 'user-1',
      notes: <LocalNoteState>[_note()],
      outbox: <PendingMutation>[_pending()],
      conflicts: <SyncConflict>[_conflict()],
      cursor: const SyncCursor('c-1'),
    );
    final LocalSyncState second = LocalSyncState(
      accountUserId: 'user-1',
      notes: <LocalNoteState>[_note()],
      outbox: <PendingMutation>[_pending()],
      conflicts: <SyncConflict>[_conflict()],
      cursor: const SyncCursor('c-1'),
    );

    expect(identical(first.notes, second.notes), isFalse);
    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect(first, isNot(LocalSyncState(accountUserId: 'user-2')));
  });
}
