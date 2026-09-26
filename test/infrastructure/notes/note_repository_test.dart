import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/note_sync_status.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_conflict.dart';
import 'package:note_ai_app/application/sync/sync_cursor.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/domain/notes/note_repository.dart' as domain;
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';

import 'note_repository_test_support.dart';

/// Creates the repository under test with the harness's injected collaborators.
NoteRepository buildRepository(FakeLocalSyncStoreFactory factory) {
  return NoteRepository(
    currentAccountUserId: () => activeAccount,
    localSyncStoreFactory: factory.create,
    generateMutationId: ids.next,
    now: clock.now,
  );
}

/// A factory whose single account already holds [state].
FakeLocalSyncStoreFactory statefulFactory(LocalSyncState state) {
  return FakeLocalSyncStoreFactory(
    initialStates: <String, LocalSyncState>{state.accountUserId: state},
  );
}

late TestClock clock;
late TestMutationIds ids;
late String activeAccount;

void main() {
  setUp(() {
    clock = TestClock();
    ids = TestMutationIds();
    activeAccount = 'user-1';
  });

  group('NoteRepository local state', () {
    test(
      'creates a new local note and queues a create at revision 0',
      () async {
        final FakeLocalSyncStoreFactory factory = FakeLocalSyncStoreFactory();
        final NoteRepository repository = buildRepository(factory);
        final Note note = testNote(
          id: 'note-1',
          title: 'First note',
          content: 'Body',
          createdAt: DateTime.utc(2026, 9, 25, 8),
        );

        await repository.save(note);

        final FakeLocalSyncStore store = factory.store('user-1');
        expect(store.replaceCount, 1);
        final LocalNoteState stored = store.state.notes.single;
        expect(stored.id, 'note-1');
        expect(stored.ownerId, 'user-1');
        expect(stored.title, 'First note');
        expect(stored.content, 'Body');
        expect(stored.createdAt, note.createdAt);
        expect(stored.updatedAt, note.updatedAt);
        expect(stored.serverRevision, 0);
        expect(stored.deletedAt, isNull);
        expect(stored.status, NoteSyncStatus.pending);

        final PendingMutation queued = store.state.outbox.single;
        expect(queued.mutationId, 'mutation-1');
        expect(queued.noteId, 'note-1');
        expect(queued.operation, SyncMutationOperation.create);
        expect(queued.baseRevision, 0);
        expect(
          queued.payload,
          const SyncNotePayload(title: 'First note', content: 'Body'),
        );
        expect(queued.createdAt, clock.value);
        expect(queued.retryCount, 0);
        expect(queued.blocked, isFalse);

        final Note? restored = await repository.findById('note-1');
        expect(restored, isNotNull);
        expect(restored!.title, 'First note');
        expect(restored.content, 'Body');
        expect(restored.createdAt, note.createdAt);
        expect(restored.updatedAt, note.updatedAt);
      },
    );

    test('preserves note order and reuses one store per account', () async {
      final FakeLocalSyncStoreFactory factory = FakeLocalSyncStoreFactory();
      final NoteRepository repository = buildRepository(factory);

      await repository.save(testNote(id: 'note-1'));
      await repository.save(testNote(id: 'note-2'));
      await repository.save(testNote(id: 'note-3'));

      expect(
        (await repository.findByOwnerId('user-1')).map((Note note) => note.id),
        <String>['note-1', 'note-2', 'note-3'],
      );
      expect(
        factory
            .store('user-1')
            .state
            .notes
            .map((LocalNoteState note) => note.id),
        <String>['note-1', 'note-2', 'note-3'],
      );
      expect(factory.createCount, 1);
    });

    test('edits a synced note and keeps its acknowledged revision', () async {
      final FakeLocalSyncStoreFactory factory = statefulFactory(
        LocalSyncState(
          accountUserId: 'user-1',
          notes: <LocalNoteState>[
            testLocalNote(
              id: 'note-1',
              title: 'Old',
              content: 'Old body',
              serverRevision: 7,
            ),
          ],
        ),
      );
      final NoteRepository repository = buildRepository(factory);

      await repository.save(
        testNote(id: 'note-1', title: 'Edited', content: 'Edited body'),
      );

      final LocalSyncState state = factory.store('user-1').state;
      expect(state.notes.single.serverRevision, 7);
      expect(state.notes.single.status, NoteSyncStatus.pending);
      final PendingMutation queued = state.outbox.single;
      expect(queued.operation, SyncMutationOperation.update);
      expect(queued.baseRevision, 7);
      expect(queued.mutationId, 'mutation-1');
      expect(
        queued.payload,
        const SyncNotePayload(title: 'Edited', content: 'Edited body'),
      );
    });

    test('coalesces repeated unsent edits with a stable id and base', () async {
      final FakeLocalSyncStoreFactory factory = statefulFactory(
        LocalSyncState(
          accountUserId: 'user-1',
          notes: <LocalNoteState>[
            testLocalNote(id: 'note-1', serverRevision: 3),
          ],
        ),
      );
      final NoteRepository repository = buildRepository(factory);
      final Note note = testNote(id: 'note-1', title: 'One', content: 'One');

      await repository.save(note);
      note.rename('Two', clock.now());
      await repository.save(note);
      note.replaceContent('Three', clock.now());
      await repository.save(note);

      final LocalSyncState state = factory.store('user-1').state;
      expect(state.outbox, hasLength(1));
      final PendingMutation queued = state.outbox.single;
      expect(queued.mutationId, 'mutation-1');
      expect(queued.operation, SyncMutationOperation.update);
      expect(queued.baseRevision, 3);
      expect(
        queued.payload,
        const SyncNotePayload(title: 'Two', content: 'Three'),
      );
      expect(state.notes.single.title, 'Two');
      expect(state.notes.single.content, 'Three');
      expect(state.notes.single.serverRevision, 3);
      expect(factory.store('user-1').replaceCount, 3);
    });

    test(
      'coalesces an edit into an unsent create with the latest payload',
      () async {
        final FakeLocalSyncStoreFactory factory = FakeLocalSyncStoreFactory();
        final NoteRepository repository = buildRepository(factory);

        await repository.save(
          testNote(id: 'note-1', title: 'Draft', content: 'Draft'),
        );
        await repository.save(
          testNote(id: 'note-1', title: 'Final', content: 'Final body'),
        );

        final LocalSyncState state = factory.store('user-1').state;
        expect(state.outbox, hasLength(1));
        final PendingMutation queued = state.outbox.single;
        expect(queued.operation, SyncMutationOperation.create);
        expect(queued.baseRevision, 0);
        expect(queued.mutationId, 'mutation-1');
        expect(
          queued.payload,
          const SyncNotePayload(title: 'Final', content: 'Final body'),
        );
        expect(state.notes.single.serverRevision, 0);
        expect(state.notes.single.status, NoteSyncStatus.pending);
      },
    );

    test('tombstones a synced note and queues the delete', () async {
      final FakeLocalSyncStoreFactory factory = statefulFactory(
        LocalSyncState(
          accountUserId: 'user-1',
          notes: <LocalNoteState>[
            testLocalNote(id: 'note-1', serverRevision: 4),
          ],
        ),
      );
      final NoteRepository repository = buildRepository(factory);

      await repository.deleteById('note-1');

      final FakeLocalSyncStore store = factory.store('user-1');
      final LocalNoteState tombstone = store.state.notes.single;
      expect(tombstone.isDeleted, isTrue);
      expect(tombstone.deletedAt, clock.value);
      expect(tombstone.updatedAt, clock.value);
      expect(tombstone.title, isEmpty);
      expect(tombstone.content, isEmpty);
      expect(tombstone.serverRevision, 4);
      expect(tombstone.status, NoteSyncStatus.pending);
      final PendingMutation queued = store.state.outbox.single;
      expect(queued.operation, SyncMutationOperation.delete);
      expect(queued.baseRevision, 4);
      expect(queued.mutationId, 'mutation-1');
      expect(queued.payload, isNull);
      expect(store.replaceCount, 1);

      expect(await repository.findById('note-1'), isNull);
      expect(await repository.findByOwnerId('user-1'), isEmpty);
    });

    test('coalesces an unsent update into a delete', () async {
      final FakeLocalSyncStoreFactory factory = statefulFactory(
        LocalSyncState(
          accountUserId: 'user-1',
          notes: <LocalNoteState>[
            testLocalNote(id: 'note-1', serverRevision: 4),
          ],
        ),
      );
      final NoteRepository repository = buildRepository(factory);

      await repository.save(
        testNote(id: 'note-1', title: 'Edited', content: 'Edited'),
      );
      await repository.deleteById('note-1');

      final FakeLocalSyncStore store = factory.store('user-1');
      final LocalSyncState state = store.state;
      expect(state.outbox, hasLength(1));
      final PendingMutation queued = state.outbox.single;
      expect(queued.mutationId, 'mutation-1');
      expect(queued.operation, SyncMutationOperation.delete);
      expect(queued.baseRevision, 4);
      expect(queued.payload, isNull);
      expect(state.notes.single.isDeleted, isTrue);
      expect(state.notes.single.serverRevision, 4);
      expect(store.replaceCount, 2);
    });

    test('removes a never-sent local create without a remote delete', () async {
      final FakeLocalSyncStoreFactory factory = FakeLocalSyncStoreFactory();
      final NoteRepository repository = buildRepository(factory);

      await repository.save(testNote(id: 'note-1'));
      await repository.deleteById('note-1');

      final FakeLocalSyncStore store = factory.store('user-1');
      expect(store.state.notes, isEmpty);
      expect(store.state.outbox, isEmpty);
      expect(store.replaceCount, 2);
      expect(await repository.findById('note-1'), isNull);
    });

    test('delete is idempotent for absent and tombstoned notes', () async {
      final FakeLocalSyncStoreFactory factory = statefulFactory(
        LocalSyncState(
          accountUserId: 'user-1',
          notes: <LocalNoteState>[
            testLocalNote(id: 'note-1', serverRevision: 2),
          ],
        ),
      );
      final NoteRepository repository = buildRepository(factory);

      await repository.deleteById('missing');
      final FakeLocalSyncStore store = factory.store('user-1');
      expect(store.replaceCount, 0);

      await repository.deleteById('note-1');
      expect(store.replaceCount, 1);

      await repository.deleteById('note-1');
      expect(store.replaceCount, 1);
      expect(store.state.notes.single.isDeleted, isTrue);
      expect(store.state.outbox, hasLength(1));
    });

    test('does not resurrect a tombstoned note under its old id', () async {
      final DateTime deletedAt = DateTime.utc(2026, 9, 25, 8);
      final PendingMutation pendingDelete = testMutation(
        mutationId: 'mutation-delete',
        noteId: 'note-1',
        operation: SyncMutationOperation.delete,
        baseRevision: 4,
      );
      final FakeLocalSyncStoreFactory factory = statefulFactory(
        LocalSyncState(
          accountUserId: 'user-1',
          notes: <LocalNoteState>[
            testLocalNote(
              id: 'note-1',
              serverRevision: 4,
              deletedAt: deletedAt,
              title: '',
              content: '',
              status: NoteSyncStatus.pending,
            ),
          ],
          outbox: <PendingMutation>[pendingDelete],
        ),
      );
      final NoteRepository repository = buildRepository(factory);
      expect(await repository.findById('note-1'), isNull);
      final FakeLocalSyncStore store = factory.store('user-1');
      final LocalSyncState before = store.state;

      await expectLater(
        repository.save(testNote(id: 'note-1', title: 'Restore')),
        throwsStateError,
      );

      expect(store.replaceCount, 0);
      expect(store.state, before);
    });

    test('preserves cursor, conflicts, and unrelated notes', () async {
      final DateTime detectedAt = DateTime.utc(2026, 9, 25, 9, 30);
      final LocalNoteState conflictedNote = testLocalNote(
        id: 'note-b',
        title: 'Local b',
        content: 'Local b',
        serverRevision: 4,
        status: NoteSyncStatus.conflict,
      );
      final PendingMutation conflictedPending = testMutation(
        mutationId: 'mutation-old',
        noteId: 'note-b',
        operation: SyncMutationOperation.update,
        baseRevision: 4,
        payload: const SyncNotePayload(title: 'Local b', content: 'Local b'),
      );
      final SyncConflict conflict = SyncConflict(
        noteId: 'note-b',
        remote: SyncNoteSnapshot(
          id: 'note-b',
          title: 'Remote b',
          content: 'Remote b',
          createdAt: DateTime.utc(2026, 9, 20),
          serverUpdatedAt: DateTime.utc(2026, 9, 24),
          revision: 5,
        ),
        local: conflictedNote,
        pending: conflictedPending,
        detectedAt: detectedAt,
      );
      final FakeLocalSyncStoreFactory factory = statefulFactory(
        LocalSyncState(
          accountUserId: 'user-1',
          notes: <LocalNoteState>[
            testLocalNote(id: 'note-a', serverRevision: 2),
            conflictedNote,
          ],
          outbox: <PendingMutation>[conflictedPending],
          conflicts: <SyncConflict>[conflict],
          cursor: const SyncCursor('opaque-cursor'),
        ),
      );
      final NoteRepository repository = buildRepository(factory);

      await expectLater(
        repository.save(testNote(id: 'note-b', title: 'Overwrite conflict')),
        throwsStateError,
      );
      await expectLater(repository.deleteById('note-b'), throwsStateError);

      await repository.save(
        testNote(id: 'note-a', title: 'Edited a', content: 'Edited a'),
      );

      final LocalSyncState state = factory.store('user-1').state;
      expect(state.cursor, const SyncCursor('opaque-cursor'));
      expect(state.conflicts.single, conflict);
      expect(state.notes.map((LocalNoteState note) => note.id), <String>[
        'note-a',
        'note-b',
      ]);
      expect(state.notes.first.title, 'Edited a');
      expect(state.notes[1], conflictedNote);
      expect(
        state.outbox.map((PendingMutation entry) => entry.mutationId),
        <String>['mutation-old', 'mutation-1'],
      );
    });

    test('hides tombstones from reads but keeps them in state', () async {
      final DateTime deletedAt = DateTime.utc(2026, 9, 24);
      final FakeLocalSyncStoreFactory factory = statefulFactory(
        LocalSyncState(
          accountUserId: 'user-1',
          notes: <LocalNoteState>[
            testLocalNote(id: 'note-1', serverRevision: 2),
            testLocalNote(
              id: 'note-2',
              serverRevision: 3,
              deletedAt: deletedAt,
              title: '',
              content: '',
            ),
          ],
        ),
      );
      final NoteRepository repository = buildRepository(factory);

      expect(await repository.findById('note-2'), isNull);
      expect(
        (await repository.findByOwnerId('user-1')).map((Note note) => note.id),
        <String>['note-1'],
      );
      expect(
        factory
            .store('user-1')
            .state
            .notes
            .map((LocalNoteState note) => note.id),
        <String>['note-1', 'note-2'],
      );
    });
  });

  group('NoteRepository attempted mutations', () {
    test(
      'preserves an attempted mutation and appends the next revision',
      () async {
        final PendingMutation attempted = testMutation(
          mutationId: 'mutation-sent',
          noteId: 'note-1',
          operation: SyncMutationOperation.create,
          baseRevision: 0,
          payload: const SyncNotePayload(title: 'Draft', content: 'Draft'),
          retryCount: 1,
          lastError: SyncErrorCode.serverUnavailable,
        );
        final FakeLocalSyncStoreFactory factory = statefulFactory(
          LocalSyncState(
            accountUserId: 'user-1',
            notes: <LocalNoteState>[
              testLocalNote(
                id: 'note-1',
                title: 'Draft',
                content: 'Draft',
                status: NoteSyncStatus.pending,
              ),
            ],
            outbox: <PendingMutation>[attempted],
          ),
        );
        final NoteRepository repository = buildRepository(factory);

        await repository.save(
          testNote(id: 'note-1', title: 'Edited', content: 'Edited body'),
        );

        final LocalSyncState state = factory.store('user-1').state;
        expect(state.outbox, hasLength(2));
        expect(state.outbox.first, attempted);
        expect(state.outbox.first.toMutation(), attempted.toMutation());
        final PendingMutation appended = state.outbox.last;
        expect(appended.mutationId, 'mutation-1');
        expect(appended.operation, SyncMutationOperation.update);
        expect(appended.baseRevision, 1);
        expect(
          appended.payload,
          const SyncNotePayload(title: 'Edited', content: 'Edited body'),
        );
        expect(appended.retryCount, 0);
        expect(state.notes.single.title, 'Edited');
        expect(state.notes.single.serverRevision, 0);
        expect(state.notes.single.status, NoteSyncStatus.pending);
      },
    );

    test(
      'preserves a blocked mutation and appends the next revision',
      () async {
        final PendingMutation blocked = testMutation(
          mutationId: 'mutation-blocked',
          noteId: 'note-1',
          operation: SyncMutationOperation.update,
          baseRevision: 5,
          payload: const SyncNotePayload(title: 'Old', content: 'Old'),
          retryCount: 2,
          lastError: SyncErrorCode.invalidMutation,
          blocked: true,
        );
        final FakeLocalSyncStoreFactory factory = statefulFactory(
          LocalSyncState(
            accountUserId: 'user-1',
            notes: <LocalNoteState>[
              testLocalNote(
                id: 'note-1',
                title: 'Old',
                content: 'Old',
                serverRevision: 5,
                status: NoteSyncStatus.failed,
              ),
            ],
            outbox: <PendingMutation>[blocked],
          ),
        );
        final NoteRepository repository = buildRepository(factory);

        await repository.save(testNote(id: 'note-1', title: 'New'));

        final LocalSyncState state = factory.store('user-1').state;
        expect(state.outbox, hasLength(2));
        expect(state.outbox.first, blocked);
        final PendingMutation appended = state.outbox.last;
        expect(appended.mutationId, 'mutation-1');
        expect(appended.operation, SyncMutationOperation.update);
        expect(appended.baseRevision, 6);
        expect(
          appended.payload,
          const SyncNotePayload(title: 'New', content: 'Content'),
        );
      },
    );

    test('keeps outbox order and coalesces into the appended entry', () async {
      final PendingMutation attempted = testMutation(
        mutationId: 'mutation-sent',
        noteId: 'note-1',
        operation: SyncMutationOperation.create,
        baseRevision: 0,
        payload: const SyncNotePayload(title: 'Draft', content: 'Draft'),
        retryCount: 1,
      );
      final PendingMutation otherNote = testMutation(
        mutationId: 'mutation-other',
        noteId: 'note-2',
        operation: SyncMutationOperation.create,
        baseRevision: 0,
        payload: const SyncNotePayload(title: 'Two', content: 'Two'),
      );
      final FakeLocalSyncStoreFactory factory = statefulFactory(
        LocalSyncState(
          accountUserId: 'user-1',
          notes: <LocalNoteState>[
            testLocalNote(
              id: 'note-1',
              title: 'Draft',
              content: 'Draft',
              status: NoteSyncStatus.pending,
            ),
            testLocalNote(
              id: 'note-2',
              title: 'Two',
              content: 'Two',
              status: NoteSyncStatus.pending,
            ),
          ],
          outbox: <PendingMutation>[attempted, otherNote],
        ),
      );
      final NoteRepository repository = buildRepository(factory);

      await repository.save(testNote(id: 'note-1', title: 'First edit'));
      await repository.save(testNote(id: 'note-1', title: 'Second edit'));

      final LocalSyncState state = factory.store('user-1').state;
      expect(
        state.outbox.map((PendingMutation entry) => entry.mutationId),
        <String>['mutation-sent', 'mutation-other', 'mutation-1'],
      );
      expect(state.outbox[1], otherNote);
      expect(state.outbox.first, attempted);
      final PendingMutation appended = state.outbox.last;
      expect(appended.mutationId, 'mutation-1');
      expect(appended.baseRevision, 1);
      expect(
        appended.payload,
        const SyncNotePayload(title: 'Second edit', content: 'Content'),
      );
      expect(state.notes.first.serverRevision, 0);
    });

    test(
      'a delete after an attempted create appends a predicted delete',
      () async {
        final PendingMutation attempted = testMutation(
          mutationId: 'mutation-sent',
          noteId: 'note-1',
          operation: SyncMutationOperation.create,
          baseRevision: 0,
          payload: const SyncNotePayload(title: 'Draft', content: 'Draft'),
          retryCount: 1,
        );
        final FakeLocalSyncStoreFactory factory = statefulFactory(
          LocalSyncState(
            accountUserId: 'user-1',
            notes: <LocalNoteState>[
              testLocalNote(
                id: 'note-1',
                title: 'Draft',
                content: 'Draft',
                status: NoteSyncStatus.pending,
              ),
            ],
            outbox: <PendingMutation>[attempted],
          ),
        );
        final NoteRepository repository = buildRepository(factory);

        await repository.deleteById('note-1');

        final LocalSyncState state = factory.store('user-1').state;
        expect(state.notes.single.isDeleted, isTrue);
        expect(state.notes.single.serverRevision, 0);
        expect(state.outbox, hasLength(2));
        expect(state.outbox.first, attempted);
        final PendingMutation appended = state.outbox.last;
        expect(appended.mutationId, 'mutation-1');
        expect(appended.operation, SyncMutationOperation.delete);
        expect(appended.baseRevision, 1);
        expect(appended.payload, isNull);
        expect(await repository.findById('note-1'), isNull);
      },
    );
  });

  group('NoteRepository account scoping', () {
    test('isolates notes per account and reuses the cached store', () async {
      final FakeLocalSyncStoreFactory factory = FakeLocalSyncStoreFactory();
      final NoteRepository repository = buildRepository(factory);

      await repository.save(testNote(id: 'mine', ownerId: 'user-1'));
      activeAccount = 'user-2';
      await repository.save(testNote(id: 'theirs', ownerId: 'user-2'));

      expect(
        (await repository.findByOwnerId('user-2')).map((Note note) => note.id),
        <String>['theirs'],
      );
      expect(await repository.findByOwnerId('user-1'), isEmpty);
      expect(await repository.findById('mine'), isNull);
      expect(factory.store('user-1').state.notes.single.id, 'mine');

      activeAccount = 'user-1';
      expect((await repository.findById('mine'))?.id, 'mine');
      expect(await repository.findByOwnerId('user-2'), isEmpty);
      expect(factory.createCount, 2);
    });

    test('returns no notes for a foreign owner', () async {
      final FakeLocalSyncStoreFactory factory = statefulFactory(
        LocalSyncState(
          accountUserId: 'user-2',
          notes: <LocalNoteState>[
            testLocalNote(id: 'theirs', ownerId: 'user-2'),
          ],
        ),
      );
      activeAccount = 'user-2';
      final NoteRepository repository = buildRepository(factory);

      expect(
        (await repository.findByOwnerId('user-2')).map((Note note) => note.id),
        <String>['theirs'],
      );
      expect(await repository.findByOwnerId('user-1'), isEmpty);
      expect(factory.stores.containsKey('user-1'), isFalse);
      expect(factory.createCount, 1);
    });

    test('rejects a Note owned by another account', () async {
      final FakeLocalSyncStoreFactory factory = FakeLocalSyncStoreFactory();
      final NoteRepository repository = buildRepository(factory);

      expect(await repository.findByOwnerId('user-1'), isEmpty);

      await expectLater(
        repository.save(testNote(id: 'foreign', ownerId: 'user-2')),
        throwsArgumentError,
      );

      final FakeLocalSyncStore store = factory.store('user-1');
      expect(store.replaceCount, 0);
      expect(store.state.isEmpty, isTrue);
    });

    test('fails closed when no account is signed in', () async {
      activeAccount = '   ';
      final NoteRepository repository = buildRepository(
        FakeLocalSyncStoreFactory(),
      );

      await expectLater(repository.findById('note-1'), throwsStateError);
      await expectLater(repository.findByOwnerId('user-1'), throwsStateError);
      await expectLater(
        repository.save(testNote(id: 'note-1')),
        throwsStateError,
      );
      await expectLater(repository.deleteById('note-1'), throwsStateError);
    });

    test('fails closed if a store returns another account state', () async {
      final FakeLocalSyncStore foreignStore = FakeLocalSyncStore(
        accountUserId: 'user-2',
        initial: LocalSyncState(
          accountUserId: 'user-2',
          notes: <LocalNoteState>[
            testLocalNote(id: 'foreign-note', ownerId: 'user-2'),
          ],
        ),
      );
      final NoteRepository repository = NoteRepository(
        currentAccountUserId: () => 'user-1',
        localSyncStoreFactory: ({required String accountUserId}) =>
            foreignStore,
        generateMutationId: ids.next,
        now: clock.now,
      );

      await expectLater(repository.findById('foreign-note'), throwsStateError);
      await expectLater(repository.findByOwnerId('user-1'), throwsStateError);
    });
  });

  group('NoteRepository atomic writes and serialization', () {
    test(
      'a failed save replace neither persists nor reports success',
      () async {
        final FakeLocalSyncStoreFactory factory = FakeLocalSyncStoreFactory();
        final NoteRepository repository = buildRepository(factory);
        await repository.findByOwnerId('user-1');
        final FakeLocalSyncStore store = factory.store('user-1');
        store.failure = StateError('disk unavailable');

        await expectLater(
          repository.save(testNote(id: 'note-1')),
          throwsStateError,
        );

        expect(store.replaceCount, 1);
        expect(store.state.notes, isEmpty);
        expect(store.state.outbox, isEmpty);
        expect(await repository.findById('note-1'), isNull);
      },
    );

    test('a failed delete replace leaves the note live', () async {
      final FakeLocalSyncStoreFactory factory = statefulFactory(
        LocalSyncState(
          accountUserId: 'user-1',
          notes: <LocalNoteState>[
            testLocalNote(id: 'note-1', serverRevision: 2),
          ],
        ),
      );
      final NoteRepository repository = buildRepository(factory);
      await repository.findById('note-1');
      final FakeLocalSyncStore store = factory.store('user-1');
      store.failure = StateError('disk unavailable');

      await expectLater(repository.deleteById('note-1'), throwsStateError);

      expect(store.state.notes.single.isDeleted, isFalse);
      expect(store.state.outbox, isEmpty);
      expect(await repository.findById('note-1'), isNotNull);
    });

    test('serializes concurrent mutations without losing one', () async {
      final FakeLocalSyncStoreFactory factory = FakeLocalSyncStoreFactory();
      final NoteRepository repository = buildRepository(factory);
      await repository.findByOwnerId('user-1');
      final FakeLocalSyncStore store = factory.store('user-1');
      store.delay = const Duration(milliseconds: 2);

      await Future.wait(<Future<void>>[
        repository.save(testNote(id: 'note-1', title: 'One')),
        repository.save(testNote(id: 'note-2', title: 'Two')),
      ]);

      expect(store.maximumActiveOperations, 1);
      expect(store.replaceCount, 2);
      expect(store.state.notes.map((LocalNoteState note) => note.id), <String>[
        'note-1',
        'note-2',
      ]);
      expect(
        store.state.outbox.map((PendingMutation entry) => entry.noteId),
        <String>['note-1', 'note-2'],
      );
    });

    test(
      'keeps a note edit when a sync checkpoint updates the same store',
      () async {
        final FakeLocalSyncStoreFactory factory = FakeLocalSyncStoreFactory();
        final NoteRepository repository = buildRepository(factory);
        await repository.findByOwnerId('user-1');
        final FakeLocalSyncStore store = factory.store('user-1');

        await Future.wait<void>(<Future<void>>[
          repository.save(testNote(id: 'note-1', title: 'Edited locally')),
          store
              .update((LocalSyncState current) {
                return LocalSyncState(
                  accountUserId: current.accountUserId,
                  notes: current.notes,
                  outbox: current.outbox,
                  conflicts: current.conflicts,
                  cursor: const SyncCursor('sync-cursor'),
                );
              })
              .then<void>((_) {}),
        ]);

        expect(store.state.cursor, const SyncCursor('sync-cursor'));
        expect(store.state.notes.single.title, 'Edited locally');
        expect(store.state.outbox.single.noteId, 'note-1');
      },
    );

    test('a read waits for a preceding mutation to commit', () async {
      final FakeLocalSyncStoreFactory factory = FakeLocalSyncStoreFactory();
      final NoteRepository repository = buildRepository(factory);
      await repository.findByOwnerId('user-1');
      final FakeLocalSyncStore store = factory.store('user-1');
      store.replaceGate = Completer<void>();

      final Future<void> save = repository.save(testNote(id: 'note-1'));
      await store.replaceStarted.future;

      bool readCompleted = false;
      final Future<Note?> read = repository.findById('note-1').then((
        Note? note,
      ) {
        readCompleted = true;
        return note;
      });
      await Future<void>.delayed(Duration.zero);
      expect(readCompleted, isFalse);

      store.replaceGate!.complete();
      await save;
      expect((await read)?.id, 'note-1');
    });
  });

  group('createNoteRepository', () {
    test('wires an account-bound repository', () async {
      final FakeLocalSyncStoreFactory factory = FakeLocalSyncStoreFactory();
      final domain.INoteRepository repository = createNoteRepository(
        currentAccountUserId: () => 'user-1',
        localSyncStoreFactory: factory.create,
        generateMutationId: ids.next,
        now: clock.now,
      );

      expect(repository, isA<NoteRepository>());

      await repository.save(testNote(id: 'note-1'));

      expect(factory.createCount, 1);
      expect(
        factory.store('user-1').state.outbox.single.operation,
        SyncMutationOperation.create,
      );
    });
  });
}
