import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/sync_conflict.dart';
import 'package:note_ai_app/application/sync/sync_conflict_resolver.dart';
import 'package:note_ai_app/application/sync/sync_state_reconciliation.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';

import '../notes/note_repository_test_support.dart' show FakeLocalSyncStore;
import 'm09_storage_fixtures.dart' as fixture;

SyncStateReconciliation merge(FakeLocalSyncStore store) =>
    SyncStateReconciliation(
      accountUserId: 'owner',
      localStore: store,
      clock: () => fixture.at,
    );

void main() {
  test('rejected frozen plain draft becomes an explicit conflict; both choices are typed', () async {
    for (final choice in [
      SyncConflictChoice.useLocal,
      SyncConflictChoice.useRemote,
    ]) {
      final local = LocalNoteState(
        id: 'n',
        ownerId: 'owner',
        title: 'Title',
        content: 'local legacy draft',
        createdAt: fixture.at,
        updatedAt: fixture.at,
        serverRevision: 7,
      );
      final pending = PendingMutation(
        mutationId: 'frozen',
        noteId: 'n',
        operation: SyncMutationOperation.update,
        baseRevision: 7,
        payload: const SyncNotePayload(
          title: 'Title',
          content: 'local legacy draft',
        ),
        createdAt: fixture.at,
        retryCount: 2,
        blocked: true,
        lastError: SyncErrorCode.documentRequiresUpgrade,
      );
      final store = FakeLocalSyncStore(
        accountUserId: 'owner',
        initial: LocalSyncState(
          accountUserId: 'owner',
          notes: [local],
          outbox: [pending],
        ),
      );
      await merge(store).applyPage(
        SyncChangesPage(
          wireVersion: 3,
          snapshots: [fixture.snapshot(document: fixture.doc(), revision: 7)],
        ),
        expectedCursor: null,
      );
      final conflict = (await store.read()).conflicts.single;
      expect(conflict.local.content, local.content);
      expect(conflict.pending, pending);
      expect(conflict.remote!.document, fixture.doc());
      final resolver = SyncConflictResolver(
        localSyncStore: store,
        generateNoteId: () => 'copy',
        generateMutationId: () => 'explicit-choice',
        now: () => fixture.at,
      );
      await resolver.resolve(
        accountUserId: 'owner',
        conflict: conflict,
        choice: choice,
      );
      final chosen = (await store.read()).notes.single;
      expect(chosen.document, isNotNull);
      expect(
        chosen.document!.plainText,
        choice == SyncConflictChoice.useLocal
            ? 'local legacy draft'
            : fixture.doc().plainText,
      );
      if (choice == SyncConflictChoice.useLocal) {
        expect(
          (await store.read()).outbox.single.mutationId,
          'explicit-choice',
        );
        expect(
          (await store.read()).outbox.single.payload!.includesDocument,
          true,
        );
      } else {
        expect((await store.read()).outbox, isEmpty);
      }
    }
  });
  test(
    'same revision V3 backfill adds document without changing legacy metadata',
    () async {
      final store = FakeLocalSyncStore(
        accountUserId: 'owner',
        initial: fixture.state(rich: false),
      );
      await merge(store).applyPage(
        SyncChangesPage(
          wireVersion: 3,
          snapshots: [fixture.snapshot(document: fixture.doc(), revision: 7)],
          nextCursor: 'typed',
        ),
        expectedCursor: 'cursor',
      );
      final state = await store.read();
      expect(state.notes.single.document, fixture.doc());
      expect(state.notes.single.pinnedAt, fixture.at);
      expect(state.notes.single.attachments.single, fixture.attachment);
      expect(state.syncWireVersion, 3);
      await merge(store).applyPage(
        SyncChangesPage(wireVersion: 2, snapshots: [], nextCursor: 'legacy'),
        expectedCursor: 'typed',
      );
      expect((await store.read()).syncWireVersion, 3);
    },
  );

  test(
    'same revision never replaces pending local draft with server document',
    () async {
      final initial = fixture.state(rich: false, queued: true);
      final store = FakeLocalSyncStore(
        accountUserId: 'owner',
        initial: initial,
      );
      await merge(store).applyPage(
        SyncChangesPage(
          wireVersion: 3,
          snapshots: [
            fixture.snapshot(document: fixture.doc(bold: true), revision: 7),
          ],
        ),
        expectedCursor: 'cursor',
      );
      expect((await store.read()).notes.single.document, null);
      expect((await store.read()).outbox.single, initial.outbox.single);
    },
  );

  test('same revision conflict refresh upgrades remote document and cloud choice keeps marks', () async {
    final local = fixture.note(), pending = fixture.pending();
    final initial = LocalSyncState(
      accountUserId: 'owner',
      notes: [local],
      outbox: [pending],
      conflicts: [
        SyncConflict(
          noteId: 'n',
          local: local,
          pending: pending,
          detectedAt: fixture.at,
          remote: fixture.snapshot(typed: false),
        ),
      ],
    );
    final store = FakeLocalSyncStore(accountUserId: 'owner', initial: initial);
    await merge(store).applyPage(
      SyncChangesPage(
        wireVersion: 3,
        snapshots: [fixture.snapshot(document: fixture.doc(bold: true))],
      ),
      expectedCursor: null,
    );
    final conflict = (await store.read()).conflicts.single;
    expect(conflict.remote!.document, fixture.doc(bold: true));
    expect(conflict.local, initial.conflicts.single.local);
    expect(conflict.pending, initial.conflicts.single.pending);
    final resolver = SyncConflictResolver(
      localSyncStore: store,
      generateNoteId: () => 'copy',
      generateMutationId: () => 'resolved',
      now: () => fixture.at,
    );
    await resolver.resolve(
      accountUserId: 'owner',
      conflict: conflict,
      choice: SyncConflictChoice.useRemote,
    );
    expect((await store.read()).notes.single.document, fixture.doc(bold: true));
    expect((await store.read()).conflicts, isEmpty);
  });

  test('capability recovery unblocks only upgrade failures; forbidden work stays blocked', () async {
    final initial = fixture.state(queued: true);
    final store = FakeLocalSyncStore(accountUserId: 'owner', initial: initial);
    final reconciler = merge(store);
    await reconciler.recordPushFailure(
      'attempt',
      const SyncFailure(code: SyncErrorCode.documentRequiresUpgrade),
    );
    final blocked = (await store.read()).outbox.single;
    expect(
      (await reconciler.retryDocumentUpgrade()).outbox.single.blocked,
      false,
    );
    expect((await store.read()).outbox.single.payload, blocked.payload);
    expect((await store.read()).outbox.single.mutationId, blocked.mutationId);
    await reconciler.recordPushFailure(
      'attempt',
      const SyncFailure(code: SyncErrorCode.forbidden),
    );
    expect(
      (await reconciler.retryDocumentUpgrade()).outbox.single.blocked,
      true,
    );
    expect((await store.read()).notes.single.document, fixture.doc());
  });
}
