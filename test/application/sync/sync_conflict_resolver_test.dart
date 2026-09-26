import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/local_sync_store.dart';
import 'package:note_ai_app/application/sync/note_sync_status.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_conflict.dart';
import 'package:note_ai_app/application/sync/sync_conflict_resolver.dart';
import 'package:note_ai_app/application/sync/sync_cursor.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';

final DateTime _time = DateTime.utc(2026, 9, 25);

LocalNoteState _note({
  String id = 'n1',
  String title = 'local',
  int revision = 2,
  DateTime? deletedAt,
  NoteSyncStatus status = NoteSyncStatus.conflict,
}) => LocalNoteState(
  id: id,
  ownerId: 'u1',
  title: title,
  content: 'body-$title',
  createdAt: _time,
  updatedAt: _time,
  serverRevision: revision,
  deletedAt: deletedAt,
  status: status,
);

SyncNoteSnapshot _remote({int revision = 5, DateTime? deletedAt}) =>
    SyncNoteSnapshot(
      id: 'n1',
      title: 'remote',
      content: 'remote-body',
      createdAt: _time,
      serverUpdatedAt: _time.add(const Duration(hours: 1)),
      revision: revision,
      deletedAt: deletedAt,
    );

SyncConflict _conflict(LocalNoteState local, {SyncNoteSnapshot? remote}) =>
    SyncConflict(
      noteId: local.id,
      remote: remote,
      local: local,
      pending: PendingMutation(
        mutationId: 'rejected',
        noteId: local.id,
        operation: local.isDeleted
            ? SyncMutationOperation.delete
            : SyncMutationOperation.update,
        baseRevision: local.serverRevision,
        payload: local.isDeleted
            ? null
            : SyncNotePayload(title: local.title, content: local.content),
        createdAt: _time,
      ),
      detectedAt: _time,
    );

final class _Store implements ILocalSyncStore {
  _Store(this.state);
  LocalSyncState state;
  int reads = 0;
  int updates = 0;
  int writes = 0;
  @override
  Future<LocalSyncState> read() async {
    reads++;
    return state;
  }

  @override
  Future<LocalSyncState> update(
    LocalSyncState Function(LocalSyncState current) transform,
  ) async {
    updates++;
    state = transform(state);
    writes++;
    return state;
  }

  @override
  Future<void> replace(LocalSyncState state) async {
    writes++;
    this.state = state;
  }
}

void main() {
  final DateTime deletedAt = _time.add(const Duration(days: 1));

  test(
    'local live over remote live queues a fresh update from current state',
    () async {
      final LocalNoteState conflictLocal = _note();
      final SyncConflict conflict = _conflict(conflictLocal, remote: _remote());
      final _Store store = _Store(
        LocalSyncState(
          accountUserId: 'u1',
          notes: <LocalNoteState>[_note(title: 'latest', revision: 2)],
          outbox: <PendingMutation>[
            conflict.pending,
            PendingMutation(
              mutationId: 'other',
              noteId: 'other',
              operation: SyncMutationOperation.delete,
              baseRevision: 3,
              createdAt: _time,
            ),
          ],
          conflicts: <SyncConflict>[conflict],
        ),
      );
      await _resolver(store).resolve(
        accountUserId: 'u1',
        conflict: conflict,
        choice: SyncConflictChoice.useLocal,
      );
      expect(store.state.notes.single.title, 'latest');
      expect(store.state.notes.single.serverRevision, 5);
      expect(store.state.notes.single.status, NoteSyncStatus.pending);
      expect(store.state.outbox.map((e) => e.mutationId), <String>[
        'other',
        'mutation-new',
      ]);
      expect(store.state.outbox.last.operation, SyncMutationOperation.update);
      expect(store.state.outbox.last.baseRevision, 5);
      expect(store.state.outbox.last.payload?.title, 'latest');
      expect(store.reads, 0);
      expect(store.updates, 1);
    },
  );

  test(
    'remote choice installs remote live as synced and drops note mutations',
    () async {
      final LocalNoteState local = _note();
      final SyncConflict conflict = _conflict(local, remote: _remote());
      final _Store store = _store(local, conflict);
      await _resolver(store).resolve(
        accountUserId: 'u1',
        conflict: conflict,
        choice: SyncConflictChoice.useRemote,
      );
      expect(store.state.notes.single.title, 'remote');
      expect(store.state.notes.single.status, NoteSyncStatus.synced);
      expect(store.state.outbox, isEmpty);
    },
  );

  test('local live cannot resurrect a remote tombstone', () async {
    final LocalNoteState local = _note();
    final SyncConflict conflict = _conflict(
      local,
      remote: _remote(deletedAt: deletedAt),
    );
    final _Store store = _store(local, conflict);
    await _resolver(store).resolve(
      accountUserId: 'u1',
      conflict: conflict,
      choice: SyncConflictChoice.useLocal,
    );
    expect(store.state.notes.map((n) => n.id), <String>['n1', 'new-note']);
    expect(store.state.notes.first.isDeleted, isTrue);
    expect(store.state.notes.first.status, NoteSyncStatus.synced);
    expect(store.state.notes.last.title, 'local');
    expect(store.state.notes.last.serverRevision, 0);
    expect(store.state.outbox.single.operation, SyncMutationOperation.create);
    expect(store.state.outbox.single.noteId, 'new-note');
  });

  test('remote tombstone choice discards local live version', () async {
    final LocalNoteState local = _note();
    final SyncConflict conflict = _conflict(
      local,
      remote: _remote(deletedAt: deletedAt),
    );
    final _Store store = _store(local, conflict);
    await _resolver(store).resolve(
      accountUserId: 'u1',
      conflict: conflict,
      choice: SyncConflictChoice.useRemote,
    );
    expect(store.state.notes.single.isDeleted, isTrue);
    expect(store.state.outbox, isEmpty);
  });

  test('local tombstone over remote live stays pending and queues delete at remote revision', () async {
    final LocalNoteState local = _note(deletedAt: deletedAt);
    final SyncConflict conflict = _conflict(local, remote: _remote());
    final _Store store = _store(local, conflict);
    await _resolver(store).resolve(
      accountUserId: 'u1',
      conflict: conflict,
      choice: SyncConflictChoice.useLocal,
    );
    expect(store.state.notes.single.title, 'local');
    expect(store.state.notes.single.isDeleted, isTrue);
    expect(store.state.notes.single.serverRevision, 5);
    expect(store.state.notes.single.status, NoteSyncStatus.pending);
    expect(store.state.outbox.single.operation, SyncMutationOperation.delete);
    expect(store.state.outbox.single.baseRevision, 5);
  });

  test('remote absence recreates a live local note at revision zero', () async {
    final LocalNoteState local = _note();
    final SyncConflict conflict = _conflict(local);
    final _Store store = _store(local, conflict);
    await _resolver(store).resolve(
      accountUserId: 'u1',
      conflict: conflict,
      choice: SyncConflictChoice.useLocal,
    );
    expect(store.state.notes.single.serverRevision, 0);
    expect(store.state.outbox.single.operation, SyncMutationOperation.create);
    expect(store.state.outbox.single.baseRevision, 0);
  });

  test('remote absence removes local tombstone for either choice', () async {
    for (final SyncConflictChoice choice in <SyncConflictChoice>[
      SyncConflictChoice.useLocal,
      SyncConflictChoice.useRemote,
    ]) {
      final LocalNoteState local = _note(deletedAt: deletedAt);
      final SyncConflict conflict = _conflict(local);
      final _Store store = _store(local, conflict);
      await _resolver(store)
          .resolve(accountUserId: 'u1', conflict: conflict, choice: choice);
      expect(store.state.notes, isEmpty);
      expect(store.state.outbox, isEmpty);
    }
  });

  test('later is a no-op without reading or persisting', () async {
    final LocalNoteState local = _note();
    final SyncConflict conflict = _conflict(local, remote: _remote());
    final _Store store = _store(local, conflict);
    await _resolver(store).resolve(
      accountUserId: 'u1',
      conflict: conflict,
      choice: SyncConflictChoice.later,
    );
    expect(store.reads, 0);
    expect(store.updates, 0);
    expect(store.writes, 0);
  });

  test('preserves other notes, outbox, conflicts, and cursor', () async {
    final LocalNoteState local = _note();
    final SyncConflict conflict = _conflict(local, remote: _remote());
    final SyncConflict other = _conflict(_note(id: 'other'));
    final SyncCursor cursor = const SyncCursor('opaque');
    final _Store store = _Store(
      LocalSyncState(
        accountUserId: 'u1',
        notes: <LocalNoteState>[
          local,
          _note(id: 'other'),
        ],
        outbox: <PendingMutation>[conflict.pending],
        conflicts: <SyncConflict>[conflict, other],
        cursor: cursor,
      ),
    );
    await _resolver(store).resolve(
      accountUserId: 'u1',
      conflict: conflict,
      choice: SyncConflictChoice.useRemote,
    );
    expect(store.state.notes.map((n) => n.id), contains('other'));
    expect(store.state.conflicts, <SyncConflict>[other]);
    expect(store.state.cursor, cursor);
  });

  test('rejects missing conflict and wrong account without writing', () async {
    final LocalNoteState local = _note();
    final SyncConflict conflict = _conflict(local, remote: _remote());
    final _Store missing = _store(local, _conflict(local));
    await expectLater(
      _resolver(missing).resolve(
        accountUserId: 'u1',
        conflict: conflict,
        choice: SyncConflictChoice.useLocal,
      ),
      throwsStateError,
    );
    final _Store wrong = _Store(LocalSyncState(accountUserId: 'u2'));
    await expectLater(
      _resolver(wrong).resolve(
        accountUserId: 'u1',
        conflict: conflict,
        choice: SyncConflictChoice.useLocal,
      ),
      throwsStateError,
    );
    expect(missing.writes, 0);
    expect(missing.updates, 1);
    expect(wrong.writes, 0);
    expect(wrong.updates, 1);
  });
}

SyncConflictResolver _resolver(_Store store) => SyncConflictResolver(
  localSyncStore: store,
  generateNoteId: () => 'new-note',
  generateMutationId: () => 'mutation-new',
  now: () => _time.add(const Duration(minutes: 1)),
);

_Store _store(LocalNoteState local, SyncConflict conflict) => _Store(
  LocalSyncState(
    accountUserId: 'u1',
    notes: <LocalNoteState>[local],
    outbox: <PendingMutation>[conflict.pending],
    conflicts: <SyncConflict>[conflict],
    cursor: const SyncCursor('opaque'),
  ),
);
