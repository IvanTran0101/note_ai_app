import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/local_sync_store.dart';
import 'package:note_ai_app/application/sync/note_sync_status.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/remote_note_data_source.dart';
import 'package:note_ai_app/application/sync/sync_coordinator_service.dart';
import 'package:note_ai_app/application/sync/sync_cursor.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_result.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/application/sync/sync_status.dart';

void main() {
  final DateTime time = DateTime.utc(2026, 1, 1);

  LocalNoteState note(
    String id, {
    String title = 'local',
    int revision = 0,
    NoteSyncStatus status = NoteSyncStatus.pending,
  }) => LocalNoteState(
    id: id,
    ownerId: 'acct',
    title: title,
    content: 'body',
    createdAt: time,
    updatedAt: time,
    serverRevision: revision,
    status: status,
  );

  PendingMutation mutation(
    String id,
    String noteId, {
    int retries = 0,
    bool blocked = false,
  }) => PendingMutation(
    mutationId: id,
    noteId: noteId,
    operation: SyncMutationOperation.update,
    baseRevision: 0,
    payload: const SyncNotePayload(title: 'local', content: 'body'),
    createdAt: time,
    retryCount: retries,
    blocked: blocked,
  );

  SyncNoteSnapshot remote(
    String id, {
    int revision = 1,
    String title = 'cloud',
  }) => SyncNoteSnapshot(
    id: id,
    title: title,
    content: 'remote',
    createdAt: time,
    serverUpdatedAt: time,
    revision: revision,
  );

  test('pushes sequentially and applies response while preserving a later local edit', () async {
    final store = MemoryStore(
      LocalSyncState(
        accountUserId: 'acct',
        notes: <LocalNoteState>[note('n', title: 'new local edit')],
        outbox: <PendingMutation>[mutation('m1', 'n'), mutation('m2', 'n')],
      ),
    );
    final remoteSource = FakeRemote()
      ..onPush = (m) async {
        if (m.mutationId == 'm2') {
          expect(store.state.notes.single.title, 'new local edit');
          expect(store.state.notes.single.status, NoteSyncStatus.pending);
        }
        return SyncMutationResult.applied(
          mutationId: m.mutationId,
          note: remote('n'),
        );
      };
    final report = await service(store, remoteSource).syncNow();
    expect(remoteSource.pushes.map((m) => m.mutationId), <String>['m1', 'm2']);
    expect(report.applied, 2);
    expect(store.state.outbox, isEmpty);
    expect(store.state.notes.single.title, 'cloud');
    expect(store.state.notes.single.status, NoteSyncStatus.synced);
  });

  test('sends the exact mutation captured by the atomic premark', () async {
    final original = mutation('m', 'n');
    final coalesced = PendingMutation(
      mutationId: original.mutationId,
      noteId: original.noteId,
      operation: original.operation,
      baseRevision: original.baseRevision,
      payload: const SyncNotePayload(title: 'coalesced', content: 'latest'),
      createdAt: original.createdAt,
    );
    final store = MemoryStore(
      LocalSyncState(
        accountUserId: 'acct',
        notes: <LocalNoteState>[note('n')],
        outbox: <PendingMutation>[original],
      ),
    );
    store.beforeUpdate = () {
      store.state = LocalSyncState(
        accountUserId: 'acct',
        notes: store.state.notes,
        outbox: <PendingMutation>[coalesced],
      );
      store.beforeUpdate = null;
    };
    final source = FakeRemote()
      ..onPush = (m) async => SyncMutationResult.applied(
        mutationId: m.mutationId,
        note: remote('n'),
      );
    await service(store, source).syncNow();
    expect(source.pushes.single.payload?.title, 'coalesced');
    expect(source.pushes.single.payload?.content, 'latest');
  });

  test('retry keeps wire mutation stable and persists attempts; exhaustion publishes failed', () async {
    final store = MemoryStore(
      LocalSyncState(
        accountUserId: 'acct',
        notes: <LocalNoteState>[note('n')],
        outbox: <PendingMutation>[mutation('m', 'n')],
      ),
    );
    final remoteSource = FakeRemote()
      ..onPush = (m) async =>
          throw const SyncFailure(code: SyncErrorCode.timeout);
    final svc = service(store, remoteSource, delay: (_) async {});
    await expectLater(svc.syncNow(), throwsA(isA<SyncFailure>()));
    expect(remoteSource.pushes, hasLength(2));
    expect(remoteSource.pushes[0], remoteSource.pushes[1]);
    expect(store.state.outbox.single.retryCount, 2);
    expect(store.state.outbox.single.lastError, SyncErrorCode.timeout);
    expect(svc.status.status, SyncStatus.failed);
  });

  test(
    'invalid mutation is durably blocked before failure is surfaced',
    () async {
      final store = MemoryStore(
        LocalSyncState(
          accountUserId: 'acct',
          notes: <LocalNoteState>[note('n')],
          outbox: <PendingMutation>[mutation('m', 'n')],
        ),
      );
      final source = FakeRemote()
        ..onPush = (m) async =>
            throw const SyncFailure(code: SyncErrorCode.invalidMutation);
      final svc = service(store, source);
      await expectLater(svc.syncNow(), throwsA(isA<SyncFailure>()));
      expect(store.state.outbox.single.blocked, isTrue);
      expect(
        store.state.outbox.single.lastError,
        SyncErrorCode.invalidMutation,
      );
      expect(store.state.notes.single.status, NoteSyncStatus.failed);
    },
  );

  test(
    'network unavailable publishes offline and rethrows the failure',
    () async {
      final store = MemoryStore(LocalSyncState(accountUserId: 'acct'));
      final source = FakeRemote()
        ..onPull = (cursor, limit) async =>
            throw const SyncFailure(code: SyncErrorCode.networkUnavailable);
      final svc = service(store, source);
      await expectLater(svc.syncNow(), throwsA(isA<SyncFailure>()));
      expect(svc.status.status, SyncStatus.offline);
    },
  );

  test(
    'a previously blocked entry stops every queued successor for its note',
    () async {
      final first = PendingMutation(
        mutationId: 'm1',
        noteId: 'n',
        operation: SyncMutationOperation.update,
        baseRevision: 0,
        payload: const SyncNotePayload(title: 'local', content: 'body'),
        createdAt: time,
        blocked: true,
      );
      final store = MemoryStore(
        LocalSyncState(
          accountUserId: 'acct',
          notes: <LocalNoteState>[note('n')],
          outbox: <PendingMutation>[first, mutation('m2', 'n')],
        ),
      );
      final source = FakeRemote();
      await service(store, source).syncNow();
      expect(source.pushes, isEmpty);
      expect(store.state.outbox, hasLength(2));
    },
  );

  test(
    'commits a final cursor even when the final page has no items',
    () async {
      final store = MemoryStore(LocalSyncState(accountUserId: 'acct'));
      final source = FakeRemote()
        ..onPull = (cursor, limit) async => SyncChangesPage(
          snapshots: const <SyncNoteSnapshot>[],
          nextCursor: 'final-cursor',
        );
      final report = await service(store, source).syncNow();
      expect(store.state.cursor?.value, 'final-cursor');
      expect(report.cursor?.value, 'final-cursor');
    },
  );

  test('conflict blocks exact entry and never sends same-note tail', () async {
    final store = MemoryStore(
      LocalSyncState(
        accountUserId: 'acct',
        notes: <LocalNoteState>[note('n')],
        outbox: <PendingMutation>[mutation('m1', 'n'), mutation('m2', 'n')],
      ),
    );
    final source = FakeRemote();
    source.onPush = (m) async => SyncMutationResult.conflict(
      mutationId: m.mutationId,
      remote: remote('n'),
    );
    source.onPull = (cursor, limit) async => SyncChangesPage(
      snapshots: <SyncNoteSnapshot>[remote('n', revision: 2)],
    );
    await service(store, source).syncNow();
    expect(source.pushes.map((m) => m.mutationId), <String>['m1']);
    expect(store.state.outbox.first.blocked, isTrue);
    expect(store.state.outbox.last.mutationId, 'm2');
    expect(store.state.notes.single.status, NoteSyncStatus.conflict);
    expect(store.state.conflicts.single.remote?.revision, 2);
  });

  test('pull replaces snapshots and cursor together without overwriting pending notes', () async {
    final store = MemoryStore(
      LocalSyncState(
        accountUserId: 'acct',
        notes: <LocalNoteState>[
          note('pending'),
          note('old', revision: 1, status: NoteSyncStatus.synced),
        ],
        outbox: <PendingMutation>[mutation('m', 'pending', blocked: true)],
        cursor: const SyncCursor('c0'),
      ),
    );
    final source = FakeRemote()
      ..onPull = (cursor, limit) async => SyncChangesPage(
        snapshots: <SyncNoteSnapshot>[
          remote('pending', revision: 9),
          remote('old', revision: 2),
          remote('new'),
        ],
        nextCursor: 'c1',
      );
    await service(store, source).syncNow();
    expect(store.state.cursor?.value, 'c1');
    expect(store.state.notes.first.title, 'local');
    expect(store.state.notes.first.status, NoteSyncStatus.pending);
    expect(
      store.state.notes.firstWhere((n) => n.id == 'old').serverRevision,
      2,
    );
    expect(store.state.notes.any((n) => n.id == 'new'), isTrue);
  });

  test(
    'coalesces in-flight callers and runs one extra pass for a change',
    () async {
      sourceCalls = 0;
      final store = MemoryStore(LocalSyncState(accountUserId: 'acct'));
      final gate = Completer<void>();
      final source = FakeRemote()
        ..onPull = (cursor, limit) async {
          if (sourceCalls++ == 0) await gate.future;
          return SyncChangesPage(snapshots: const <SyncNoteSnapshot>[]);
        };
      final svc = service(store, source);
      final first = svc.syncNow();
      final second = svc.syncNow();
      expect(identical(first, second), isTrue);
      gate.complete();
      await first;
      expect(sourceCalls, 2);
    },
  );

  test('dispose closes the status stream and is idempotent', () async {
    final svc = service(
      MemoryStore(LocalSyncState(accountUserId: 'acct')),
      FakeRemote(),
    );
    await svc.dispose();
    await svc.dispose();
    await expectLater(svc.statusChanges, emitsDone);
    await expectLater(svc.syncNow(), throwsA(isA<SyncFailure>()));
  });

  test(
    'rejects account mismatch and fails safely on a non-advancing more page',
    () async {
      final wrong = MemoryStore(LocalSyncState(accountUserId: 'other'));
      final mismatch = service(wrong, FakeRemote());
      await expectLater(mismatch.syncNow(), throwsA(isA<SyncFailure>()));
      expect(mismatch.status.status, SyncStatus.failed);

      final store = MemoryStore(
        LocalSyncState(accountUserId: 'acct', cursor: const SyncCursor('c')),
      );
      final source = FakeRemote()
        ..onPull = (cursor, limit) async => SyncChangesPage(
          snapshots: const <SyncNoteSnapshot>[],
          nextCursor: 'c',
          hasMore: true,
        );
      await expectLater(
        service(store, source).syncNow(),
        throwsA(isA<SyncFailure>()),
      );
      expect(store.state.cursor?.value, 'c');
    },
  );
}

int sourceCalls = 0;

SyncCoordinatorService service(
  MemoryStore store,
  FakeRemote remoteSource, {
  Future<void> Function(Duration)? delay,
}) => SyncCoordinatorService(
  accountUserId: 'acct',
  localStore: store,
  remote: remoteSource,
  clock: () => DateTime.utc(2026, 1, 1),
  delay: delay,
);

final class MemoryStore implements ILocalSyncStore {
  MemoryStore(this.state);
  LocalSyncState state;
  void Function()? beforeUpdate;
  @override
  Future<LocalSyncState> read() async => state;
  @override
  Future<LocalSyncState> update(
    LocalSyncState Function(LocalSyncState current) transform,
  ) async {
    beforeUpdate?.call();
    return state = transform(state);
  }

  @override
  Future<void> replace(LocalSyncState value) async => state = value;
}

final class FakeRemote implements IRemoteNoteDataSource {
  final List<SyncMutation> pushes = <SyncMutation>[];
  Future<SyncMutationResult> Function(SyncMutation)? onPush;
  Future<SyncChangesPage> Function(String?, int)? onPull;
  @override
  Future<SyncMutationResult> push(SyncMutation mutation) {
    pushes.add(mutation);
    return onPush?.call(mutation) ??
        Future<SyncMutationResult>.error(
          const SyncFailure(code: SyncErrorCode.unexpected),
        );
  }

  @override
  Future<SyncChangesPage> pull({String? cursor, int limit = 50}) =>
      onPull?.call(cursor, limit) ??
      Future<SyncChangesPage>.value(
        SyncChangesPage(snapshots: const <SyncNoteSnapshot>[]),
      );
}
