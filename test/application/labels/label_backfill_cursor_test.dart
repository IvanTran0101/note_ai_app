import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/note_sync_status.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_coordinator_service.dart';
import 'package:note_ai_app/application/sync/sync_cursor.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/application/sync/sync_status.dart';

import '../sync/sync_coordinator_service_test.dart' as fixtures;

void main() {
  final time = DateTime.utc(2026, 10, 13);

  test('legacy backfill may end its first page at the stored cursor', () async {
    final frozen = PendingMutation(
      mutationId: 'blocked-attempt',
      noteId: 'retained-draft',
      operation: SyncMutationOperation.update,
      baseRevision: 1,
      payload: const SyncNotePayload(
        title: 'Retained',
        content: 'Private draft',
      ),
      createdAt: time,
      retryCount: 1,
      lastError: SyncErrorCode.forbidden,
      blocked: true,
    );
    final store = fixtures.MemoryStore(
      LocalSyncState(
        accountUserId: 'acct',
        syncWireVersion: 1,
        cursor: const SyncCursor('page-50'),
        notes: [
          LocalNoteState(
            id: 'retained-draft',
            ownerId: 'acct',
            title: 'Retained',
            content: 'Private draft',
            createdAt: time,
            updatedAt: time,
            serverRevision: 1,
            status: NoteSyncStatus.pending,
          ),
        ],
        outbox: [frozen],
      ),
    );
    final cursors = <String?>[];
    final remote = fixtures.FakeRemote()
      ..onPull = (cursor, limit) async {
        cursors.add(cursor);
        final first = cursors.length == 1;
        return SyncChangesPage(
          snapshots: [
            SyncNoteSnapshot(
              id: first ? 'first-page-note' : 'last-page-note',
              title: 'Backfilled',
              content: 'Cloud body',
              revision: 1,
              createdAt: time,
              serverUpdatedAt: time,
            ),
          ],
          wireVersion: 2,
          nextCursor: first ? 'page-50' : 'page-51',
          hasMore: first,
        );
      };
    final service = SyncCoordinatorService(
      accountUserId: 'acct',
      localStore: store,
      remote: remote,
      labelsEnabled: true,
    );
    addTearDown(service.dispose);

    await service.syncNow();

    expect(cursors, [null, 'page-50']);
    expect(store.state.syncWireVersion, 2);
    expect(store.state.cursor, const SyncCursor('page-51'));
    expect(
      store.state.notes.map((note) => note.id),
      containsAll(['retained-draft', 'first-page-note', 'last-page-note']),
    );
    expect(store.state.outbox.single, same(frozen));
    expect(store.state.notes.first.content, 'Private draft');
    expect(remote.pushes, isEmpty);
    expect(service.status.status, SyncStatus.idle);
  });

  test(
    'negotiated V2 still rejects a page that repeats the requested cursor',
    () async {
      final store = fixtures.MemoryStore(
        LocalSyncState(
          accountUserId: 'acct',
          cursor: const SyncCursor('page-50'),
        ),
      );
      final remote = fixtures.FakeRemote()
        ..onPull = (cursor, limit) async => SyncChangesPage(
          snapshots: [],
          wireVersion: 2,
          nextCursor: cursor,
          hasMore: true,
        );
      final service = SyncCoordinatorService(
        accountUserId: 'acct',
        localStore: store,
        remote: remote,
        labelsEnabled: true,
      );
      addTearDown(service.dispose);

      await expectLater(
        service.syncNow(),
        throwsA(
          isA<SyncFailure>().having(
            (failure) => failure.code,
            'code',
            SyncErrorCode.unexpected,
          ),
        ),
      );
      expect(store.state.cursor, const SyncCursor('page-50'));
    },
  );
}
