import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/labels/local_label_state.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/note_sync_status.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/remote_note_data_source.dart';
import 'package:note_ai_app/application/sync/sync_coordinator_service.dart';
import 'package:note_ai_app/application/sync/sync_cursor.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_result.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/application/sync/sync_state_reconciliation.dart';
import 'package:note_ai_app/domain/labels/label_membership.dart';

import '../../infrastructure/notes/note_repository_test_support.dart';

final time = DateTime.utc(2026, 10, 4);
LocalLabelState label({String owner = 'owner', int revision = 0}) =>
    LocalLabelState(
      id: 'same',
      ownerId: owner,
      name: 'Việt Nam',
      createdAt: time,
      updatedAt: time,
      serverRevision: revision,
      status: revision == 0 ? NoteSyncStatus.pending : NoteSyncStatus.synced,
    );
PendingMutation pending({bool catalog = false}) => PendingMutation(
  mutationId: catalog ? 'label-write' : 'note-write',
  noteId: 'same',
  entityType: catalog ? SyncEntityType.label : SyncEntityType.note,
  labelName: catalog ? 'Việt Nam' : null,
  operation: SyncMutationOperation.create,
  baseRevision: 0,
  createdAt: time,
  payload: catalog
      ? null
      : SyncNotePayload(
          title: 'Title',
          content: 'Body',
          includesLabels: true,
          labelMembership: LabelMembership(['same']),
        ),
);
LocalNoteState note() => LocalNoteState(
  id: 'same',
  ownerId: 'owner',
  title: 'Title',
  content: 'Body',
  createdAt: time,
  updatedAt: time,
  labelIds: ['same'],
);
SyncNoteSnapshot snapshot(SyncMutation m) => SyncNoteSnapshot(
  id: m.noteId,
  title: 'Title',
  content: 'Body',
  revision: 1,
  createdAt: time,
  serverUpdatedAt: time,
  includesLabels: true,
  labelIds: ['same'],
);

final class Remote implements IRemoteNoteDataSource {
  final sent = <SyncMutation>[], cursors = <String?>[];
  Future<SyncMutationResult> Function(SyncMutation)? onPush;
  @override
  Future<SyncMutationResult> push(SyncMutation m) async {
    sent.add(m);
    if (onPush != null) return onPush!(m);
    return m.entityType == SyncEntityType.label
        ? SyncMutationResult.labelApplied(
            mutationId: m.mutationId,
            label: label(revision: 1),
          )
        : SyncMutationResult.applied(
            mutationId: m.mutationId,
            note: snapshot(m),
          );
  }

  @override
  Future<SyncChangesPage> pull({String? cursor, int limit = 50}) async {
    cursors.add(cursor);
    return SyncChangesPage(
      snapshots: [],
      wireVersion: 2,
      nextCursor: 'typed-cursor',
    );
  }
}

void main() {
  FakeLocalSyncStore store() => FakeLocalSyncStore(
    accountUserId: 'owner',
    initial: LocalSyncState(
      accountUserId: 'owner',
      notes: [note()],
      labels: [label()],
      outbox: [pending(), pending(catalog: true)],
    ),
  );
  SyncCoordinatorService coordinator(FakeLocalSyncStore s, Remote r) =>
      SyncCoordinatorService(
        accountUserId: 'owner',
        localStore: s,
        remote: r,
        clock: () => time,
        labelsEnabled: true,
      );
  test(
    'same-ID label ACK precedes dependent earlier Note and preserves both',
    () async {
      final s = store(), r = Remote(), c = coordinator(s, r);
      addTearDown(c.dispose);
      final report = await c.syncNow();
      expect(report.applied, 2);
      expect(r.sent.map((m) => m.entityType), [
        SyncEntityType.label,
        SyncEntityType.note,
      ]);
      expect(s.state.labels.single.serverRevision, 1);
      expect(s.state.notes.single.serverRevision, 1);
      expect(s.state.notes.single.labelIds, ['same']);
      expect(s.state.outbox, isEmpty);
    },
  );
  test(
    'wrong label ACK revision cannot consume the attempted mutation',
    () async {
      final s = store(),
          r = Remote()
            ..onPush = (m) async => SyncMutationResult.labelApplied(
              mutationId: m.mutationId,
              label: label(revision: 8),
            );
      final c = coordinator(s, r);
      addTearDown(c.dispose);
      await expectLater(c.syncNow(), throwsA(isA<SyncFailure>()));
      expect(s.state.outbox.length, 2);
      expect(s.state.labels.single.serverRevision, 0);
    },
  );
  test('foreign catalog page is rejected atomically with its cursor', () async {
    final s = store();
    final before = s.state;
    final recon = SyncStateReconciliation(
      accountUserId: 'owner',
      localStore: s,
      clock: () => time,
    );
    await expectLater(
      recon.applyPage(
        SyncChangesPage(
          snapshots: [],
          labels: [label(owner: 'other', revision: 1)],
          wireVersion: 2,
          nextCursor: 'bad',
        ),
        expectedCursor: null,
      ),
      throwsA(isA<SyncFailure>()),
    );
    expect(s.state, before);
  });
  test('legacy cursor is rewound only by a successful v2 checkpoint', () async {
    final s = FakeLocalSyncStore(
      accountUserId: 'owner',
      initial: LocalSyncState(
        accountUserId: 'owner',
        cursor: const SyncCursor('legacy-cursor'),
        syncWireVersion: 1,
      ),
    );
    final r = Remote(), c = coordinator(s, r);
    addTearDown(c.dispose);
    await c.syncNow();
    expect(r.cursors, [null]);
    expect(s.state.syncWireVersion, 2);
    expect(s.state.cursor?.value, 'typed-cursor');
    await c.syncNow();
    expect(r.cursors.last, 'typed-cursor');
  });
  test(
    'invalid Label does not collide with same-ID independent Note',
    () async {
      final s = FakeLocalSyncStore(
        accountUserId: 'owner',
        initial: LocalSyncState(
          accountUserId: 'owner',
          labels: [label()],
          notes: [
            LocalNoteState(
              id: 'same',
              ownerId: 'owner',
              title: 'Title',
              content: 'Body',
              createdAt: time,
              updatedAt: time,
            ),
          ],
          outbox: [
            pending(catalog: true),
            PendingMutation(
              mutationId: 'note-write',
              noteId: 'same',
              operation: SyncMutationOperation.create,
              baseRevision: 0,
              payload: const SyncNotePayload(title: 'Title', content: 'Body'),
              createdAt: time,
            ),
          ],
        ),
      );
      final r = Remote()
        ..onPush = (m) async {
          if (m.entityType == SyncEntityType.label) {
            throw const SyncFailure(code: SyncErrorCode.invalidMutation);
          }
          return SyncMutationResult.applied(
            mutationId: m.mutationId,
            note: snapshot(m),
          );
        };
      final c = coordinator(s, r);
      addTearDown(c.dispose);
      await expectLater(c.syncNow(), throwsA(isA<SyncFailure>()));
      expect(s.state.outbox.single.isLabel, true);
      expect(s.state.outbox.single.blocked, true);
      expect(s.state.notes.single.serverRevision, 1);
    },
  );
}
