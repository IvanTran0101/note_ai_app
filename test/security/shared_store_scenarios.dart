import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/application/sync/sync_state_reconciliation.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/domain/notes/note_role.dart';
import 'package:note_ai_app/domain/notes/note_share_grant.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store.dart';

void registerSharedStoreScenarios() {
  final at = DateTime.utc(2026, 10, 2);
  NoteShareGrant grant(String actor, {int revision = 1, bool active = true}) =>
      NoteShareGrant(
        note: NoteIdentity('canonical-owner', 'same'),
        recipientId: actor,
        role: NoteRole.editor,
        sharedAt: at,
        updatedAt: at,
        accessRevision: revision,
        status: active ? NoteShareStatus.active : NoteShareStatus.revoked,
        revokedAt: active ? null : at,
      );
  LocalNoteState owned(String actor) => LocalNoteState(
    id: 'same',
    ownerId: actor,
    title: 'owned title',
    content: 'owned secret',
    createdAt: at,
    updatedAt: at,
    serverRevision: 7,
  );
  LocalNoteState shared(
    String actor, {
    bool available = true,
    NoteProtection p = const NoteProtection.unprotected(),
  }) => LocalNoteState(
    id: 'same',
    ownerId: 'canonical-owner',
    share: grant(actor),
    title: available ? 'shared title' : '',
    content: available ? 'shared draft' : '',
    createdAt: at,
    updatedAt: at,
    serverRevision: 7,
    contentAvailable: available,
    protection: p,
  );
  SyncNoteSnapshot snapshot(
    String actor, {
    int access = 1,
    bool active = true,
    int revision = 7,
    NoteProtection p = const NoteProtection.unprotected(),
  }) => SyncNoteSnapshot(
    id: 'same',
    ownerId: 'canonical-owner',
    share: grant(actor, revision: access, active: active),
    title: active ? 'cloud title' : '',
    content: active ? 'cloud body' : '',
    createdAt: at,
    serverUpdatedAt: at,
    revision: revision,
    contentAvailable: active,
    protection: p,
  );
  EncryptedSyncStore open(String actor) =>
      createLocalSyncStore(accountUserId: actor) as EncryptedSyncStore;

  test('real actor storage keeps same-id protected owned/shared notes independently unlockable', () async {
    final actor = 'm06-pair-${DateTime.now().microsecondsSinceEpoch}';
    final store = open(actor);
    addTearDown(store.dispose);
    final p = NoteProtection(enabled: true, revision: 1);
    await store.replace(
      LocalSyncState(
        accountUserId: actor,
        notes: [
          owned(actor),
          shared(actor, available: false, p: p),
        ],
      ),
    );
    await store.seal('same', 'owned-test-password', p);
    final reference = grant(actor).note.referenceFor(actor);
    await store.unlock(
      reference,
      'shared-test-password',
      p,
      verifiedOnline: true,
    );
    await store.hydrate(snapshot(actor, p: p));
    store.lock(reference);
    var state = await store.read();
    expect(
      state.notes.firstWhere((n) => n.ownerId == actor).content,
      'owned secret',
    );
    expect(
      state.notes.firstWhere((n) => n.ownerId != actor).contentAvailable,
      false,
    );
    await expectLater(
      store.unlock(reference, 'owned-test-password', p),
      throwsA(isA<NoteSecurityFailure>()),
    );
    await store.unlock(reference, 'shared-test-password', p);
    expect(
      (await store.read()).notes.firstWhere((n) => n.ownerId != actor).content,
      'cloud body',
    );
    store.dispose();
    final reopened = open(actor);
    addTearDown(reopened.dispose);
    await reopened.unlock('same', 'owned-test-password', p);
    await reopened.unlock(reference, 'shared-test-password', p);
    state = await reopened.read();
    expect(
      state.notes.map((n) => n.content),
      containsAll(['owned secret', 'cloud body']),
    );
    expect(
      state.outbox,
      isEmpty,
      reason: 'hydration never queues duplicate writes',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('revoke applies before pending/revision skip, retains encrypted work and re-share never replays old epoch', () async {
    final actor = 'm06-access-${DateTime.now().microsecondsSinceEpoch}';
    final store = open(actor);
    addTearDown(store.dispose);
    final pending = PendingMutation(
      mutationId: 'original-id',
      noteId: 'same',
      ownerId: 'canonical-owner',
      accessRevision: 1,
      operation: SyncMutationOperation.update,
      baseRevision: 7,
      payload: const SyncNotePayload(
        title: 'shared title',
        content: 'shared draft',
      ),
      createdAt: at,
      retryCount: 3,
    );
    await store.replace(
      LocalSyncState(
        accountUserId: actor,
        notes: [owned(actor), shared(actor)],
        outbox: [pending],
      ),
    );
    final reconcile = SyncStateReconciliation(
      accountUserId: actor,
      localStore: store,
      clock: () => at,
    );
    await reconcile.applyPage(
      SyncChangesPage(
        snapshots: [snapshot(actor, access: 2, active: false)],
        nextCursor: 'access-2',
      ),
      expectedCursor: null,
    );
    var state = await store.read();
    final removed = state.notes.firstWhere((n) => n.ownerId != actor);
    expect(removed.share!.isActive, false);
    expect(removed.contentAvailable, false);
    expect(
      removed.isDeleted,
      false,
      reason: 'revoke does not tombstone canonical owner content',
    );
    expect(
      state.notes.firstWhere((n) => n.ownerId == actor).content,
      'owned secret',
    );
    expect(state.outbox.single.mutationId, 'original-id');
    expect(state.outbox.single.baseRevision, 7);
    expect(state.outbox.single.retryCount, 3);
    expect(state.outbox.single.blocked, true);
    expect(state.outbox.single.payload!.content, isEmpty);
    expect(
      store.hasRetainedCiphertext(grant(actor).note.referenceFor(actor)),
      true,
    );
    await reconcile.applyPage(
      SyncChangesPage(
        snapshots: [snapshot(actor, access: 3)],
        nextCursor: 'access-3',
      ),
      expectedCursor: 'access-2',
    );
    state = await store.read();
    expect(
      state.notes.firstWhere((n) => n.ownerId != actor).content,
      'cloud body',
    );
    expect(state.outbox.single.blocked, true);
    expect(state.outbox.single.accessRevision, 1);
    await reconcile.applyPage(
      SyncChangesPage(
        snapshots: [snapshot(actor, access: 2, active: false)],
        nextCursor: 'stale',
      ),
      expectedCursor: 'access-3',
    );
    expect(
      (await store.read()).notes
          .firstWhere((n) => n.ownerId != actor)
          .share!
          .accessRevision,
      3,
    );
    store.dispose();
    final reopened = open(actor);
    addTearDown(reopened.dispose);
    expect((await reopened.read()).outbox.single.blocked, true);
    expect(
      reopened.hasRetainedCiphertext(grant(actor).note.referenceFor(actor)),
      true,
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
