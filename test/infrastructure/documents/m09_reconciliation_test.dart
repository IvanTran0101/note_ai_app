import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/sync_state_reconciliation.dart';
import 'package:note_ai_app/application/sync/sync_conflict_resolver.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/sync_conflict.dart';
import 'package:note_ai_app/application/labels/normalize_label_dispatch.dart';
import 'package:note_ai_app/application/labels/local_label_state.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/domain/labels/label_membership.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_state_codec.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_codec_exception.dart';
import 'package:note_ai_app/infrastructure/sync/sync_http_mapper.dart';

import '../notes/note_repository_test_support.dart' show FakeLocalSyncStore;
import 'm09_storage_fixtures.dart' as fixture;

void main() {
  test('schema6 migration keeps attempted legacy payload bytes and no virtual document', () {
    final old = LocalSyncStateCodec.encode(
      fixture.state(rich: false, queued: true, retryCount: 3),
    );
    old['schemaVersion'] = 6;
    final decoded = LocalSyncStateCodec.decode(old);
    expect(decoded.notes.single.document, null);
    expect(LocalSyncStateCodec.encode(decoded)['outbox'], old['outbox']);
    expect(decoded.outbox.single.mutationId, 'attempt');
    expect(decoded.outbox.single.retryCount, 3);
    expect(decoded.cursor!.value, 'cursor');
    (old['notes'] as List).single['document'] = null;
    expect(
      () => LocalSyncStateCodec.decode(old),
      throwsA(isA<LocalSyncCodecException>()),
    );
  });

  test(
    'rich payload uses explicit V3; frozen plain payload stays unchanged',
    () {
      final rich = encodeSyncMutation(fixture.pending().toMutation());
      expect(rich['wireVersion'], 3);
      expect(rich['documentCapability'], 'basicBlocksV1');
      expect((rich['payload'] as Map).containsKey('document'), true);
      expect(
        encodeSyncMutation(
          fixture.pending(rich: false).toMutation(),
        )['payload'],
        {'title': 'Title', 'content': fixture.doc().plainText},
      );
    },
  );

  test(
    'ACK without typed document refuses and leaves the complete pending state',
    () async {
      final initial = fixture.state(queued: true);
      final store = FakeLocalSyncStore(
        accountUserId: 'owner',
        initial: initial,
      );
      final merge = SyncStateReconciliation(
        accountUserId: 'owner',
        localStore: store,
        clock: () => fixture.at,
      );
      await expectLater(
        merge.acknowledge(
          initial.outbox.single,
          fixture.snapshot(typed: false),
        ),
        throwsA(isA<SyncFailure>()),
      );
      expect(await store.read(), initial);
      expect(
        await merge.acknowledge(
          initial.outbox.single,
          fixture.snapshot(document: fixture.doc()),
        ),
        true,
      );
      expect((await store.read()).notes.single.document, fixture.doc());
      expect((await store.read()).outbox, isEmpty);
    },
  );

  test('metadata/status and pending label refresh retain document; unavailable pull masks it', () async {
    final grant = fixture.grant();
    final initial = fixture.state(queued: true, share: grant);
    final store = FakeLocalSyncStore(accountUserId: 'actor', initial: initial);
    final merge = SyncStateReconciliation(
      accountUserId: 'actor',
      localStore: store,
      clock: () => fixture.at,
    );
    expect(
      merge
          .withStatus(initial.notes.single, initial.notes.single.status)
          .document,
      fixture.doc(),
    );
    await merge.applyPage(
      SyncChangesPage(
        snapshots: [fixture.snapshot(document: fixture.doc(), share: grant)],
        nextCursor: 'next',
      ),
      expectedCursor: 'cursor',
    );
    expect((await store.read()).notes.single.document, fixture.doc());
    final hidden = merge.fromRemote(
      fixture.snapshot(available: false, share: grant),
      initial.notes.single.status,
      previous: initial.notes.single,
    );
    expect(hidden.document, null);
    expect(hidden.content, isEmpty);
  });

  test('explicit conflict local choice/copy and remote choice retain document and metadata', () async {
    for (final choice in [
      SyncConflictChoice.useLocal,
      SyncConflictChoice.useRemote,
    ]) {
      for (final deleted in [false, true]) {
        if (deleted && choice == SyncConflictChoice.useRemote) continue;
        final ordinary = fixture.note();
        final local = LocalNoteState(
          id: ordinary.id,
          ownerId: ordinary.ownerId,
          title: ordinary.title,
          content: ordinary.content,
          document: ordinary.document,
          createdAt: ordinary.createdAt,
          updatedAt: ordinary.updatedAt,
          labelIds: ordinary.labelIds,
          pinnedAt: ordinary.pinnedAt,
          serverRevision: 7,
        );
        final remote = fixture.snapshot(
          document: fixture.doc(bold: true),
          deleted: deleted,
        );
        final pending = fixture.pending();
        final conflict = SyncConflict(
          noteId: 'n',
          local: local,
          pending: pending,
          remote: remote,
          detectedAt: fixture.at,
        );
        final initial = LocalSyncState(
          accountUserId: 'owner',
          notes: [local],
          outbox: [pending],
          conflicts: [conflict],
        );
        final store = FakeLocalSyncStore(
          accountUserId: 'owner',
          initial: initial,
        );
        final resolver = SyncConflictResolver(
          localSyncStore: store,
          generateNoteId: () => 'copy',
          generateMutationId: () => 'resolved',
          now: () => fixture.at,
        );
        await resolver.resolve(
          accountUserId: 'owner',
          conflict: conflict,
          choice: choice,
        );
        final result = await store.read();
        final live = result.notes.where((n) => !n.isDeleted).single;
        expect(
          live.document,
          choice == SyncConflictChoice.useLocal
              ? fixture.doc()
              : fixture.doc(bold: true),
        );
        if (choice == SyncConflictChoice.useLocal) {
          expect(result.outbox.single.payload!.document, fixture.doc());
          expect(live.pinnedAt, fixture.at);
          expect(live.labelIds, ['label']);
        }
        expect(result.conflicts, isEmpty);
      }
    }
  });

  test('label dispatch normalization preserves document presence/marks', () {
    final membership = LabelMembership(['gone']);
    final m = PendingMutation(
      mutationId: 'm',
      noteId: 'n',
      operation: SyncMutationOperation.update,
      baseRevision: 7,
      createdAt: fixture.at,
      payload: SyncNotePayload(
        title: 'Title',
        content: fixture.doc().plainText,
        document: fixture.doc(),
        includesDocument: true,
        labelMembership: membership,
        includesLabels: true,
      ),
    );
    final state = LocalSyncState(
      accountUserId: 'owner',
      labels: [
        LocalLabelState(
          id: 'gone',
          ownerId: 'owner',
          name: 'Gone',
          createdAt: fixture.at,
          updatedAt: fixture.at,
          deletedAt: fixture.at,
        ),
      ],
      notes: [fixture.note()],
      outbox: [m],
    );
    final normalized = normalizeLabelDispatch(state, m);
    expect(normalized.payload!.labelIds, isEmpty);
    expect(normalized.payload!.document, fixture.doc());
    expect(normalized.payload!.includesDocument, true);
  });
}
