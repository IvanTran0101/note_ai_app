import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_conflict.dart';
import 'package:note_ai_app/application/sync/sync_conflict_resolver.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_result.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_role.dart';
import 'package:note_ai_app/domain/notes/note_share_grant.dart';

import 'sync_coordinator_service_test.dart' as fixtures;

final _at = DateTime.utc(2026, 10, 2);
NoteShareGrant _grant({NoteRole role = NoteRole.editor}) => NoteShareGrant(
  note: NoteIdentity('canonical-owner', 'same'),
  recipientId: 'acct',
  role: role,
  sharedAt: _at,
  updatedAt: _at,
  accessRevision: 3,
);
LocalNoteState _note(String owner, {NoteRole role = NoteRole.editor}) =>
    LocalNoteState(
      id: 'same',
      ownerId: owner,
      share: owner == 'acct' ? null : _grant(role: role),
      title: '$owner title',
      content: '$owner body',
      createdAt: _at,
      updatedAt: _at,
      serverRevision: 7,
    );
PendingMutation _pending(String owner, {bool blocked = false}) =>
    PendingMutation(
      mutationId: '$owner-mutation',
      noteId: 'same',
      ownerId: owner == 'acct' ? null : owner,
      accessRevision: owner == 'acct' ? null : 3,
      operation: SyncMutationOperation.update,
      baseRevision: 7,
      payload: const SyncNotePayload(title: 'draft', content: 'draft body'),
      createdAt: _at,
      retryCount: 3,
      blocked: blocked,
    );
SyncNoteSnapshot _remote(String owner, {bool deleted = false}) =>
    SyncNoteSnapshot(
      id: 'same',
      ownerId: owner,
      share: owner == 'acct' ? null : _grant(),
      title: 'cloud',
      content: 'cloud body',
      revision: 8,
      createdAt: _at,
      serverUpdatedAt: _at,
      deletedAt: deleted ? _at : null,
    );

void main() {
  for (final blocked in [false, true]) {
    test(
      'shared denial/blocked=$blocked never stops an owned same-id queue',
      () async {
        final store = fixtures.MemoryStore(
          LocalSyncState(
            accountUserId: 'acct',
            notes: [_note('canonical-owner'), _note('acct')],
            outbox: [
              _pending('canonical-owner', blocked: blocked),
              _pending('acct'),
            ],
          ),
        );
        var pulls = 0;
        final remote = fixtures.FakeRemote()
          ..onPush = (m) async {
            if (m.ownerId != null) {
              throw const SyncFailure(code: SyncErrorCode.forbidden);
            }
            return SyncMutationResult.applied(
              mutationId: m.mutationId,
              note: _remote('acct'),
            );
          }
          ..onPull = (cursor, limit) async {
            pulls++;
            return SyncChangesPage(snapshots: [], nextCursor: 'finished');
          };
        final svc = fixtures.service(store, remote);
        addTearDown(svc.dispose);
        final report = await svc.syncNow();
        expect(report.applied, 1);
        expect(pulls, 1);
        expect(
          remote.pushes.map((m) => m.ownerId),
          blocked ? [null] : ['canonical-owner', null],
        );
        expect(
          store.state.notes.firstWhere((n) => n.ownerId == 'acct').content,
          'cloud body',
        );
        expect(store.state.outbox.single.ownerId, 'canonical-owner');
        expect(store.state.outbox.single.baseRevision, 7);
        expect(store.state.outbox.single.retryCount, blocked ? 3 : 4);
        expect(store.state.outbox.single.blocked, true);
        expect(store.state.cursor!.value, 'finished');
      },
    );
  }

  for (final role in NoteRole.values) {
    test(
      'shared conflict resolution uses canonical pair and role ${role.name}',
      () async {
        final local = _note('canonical-owner', role: role);
        final pending = _pending('canonical-owner', blocked: true);
        final conflict = SyncConflict(
          noteId: 'same',
          local: local,
          pending: pending,
          remote: _remote('canonical-owner'),
          detectedAt: _at,
        );
        final store = fixtures.MemoryStore(
          LocalSyncState(
            accountUserId: 'acct',
            notes: [local, _note('acct')],
            outbox: [pending, _pending('acct')],
            conflicts: [conflict],
          ),
        );
        final resolver = SyncConflictResolver(
          localSyncStore: store,
          generateNoteId: () => 'new',
          generateMutationId: () => 'reviewed',
          now: () => _at,
        );
        final action = resolver.resolve(
          accountUserId: 'acct',
          conflict: conflict,
          choice: SyncConflictChoice.useLocal,
        );
        if (role == NoteRole.viewer) {
          await expectLater(action, throwsA(isA<NoteSecurityFailure>()));
          expect(store.state.conflicts, [conflict]);
        } else {
          await action;
          final next = store.state.outbox.firstWhere((m) => m.ownerId != null);
          expect(next.ownerId, 'canonical-owner');
          expect(next.accessRevision, 3);
          expect(next.baseRevision, 8);
          expect(
            store.state.notes.firstWhere((n) => n.ownerId == 'acct').title,
            'acct title',
          );
          expect(
            store.state.outbox.firstWhere((m) => m.ownerId == null).mutationId,
            'acct-mutation',
          );
        }
      },
    );
  }
  test('recipient cannot recreate or clone a deleted canonical note from a conflict', () async {
    final local = _note('canonical-owner');
    final pending = _pending('canonical-owner', blocked: true);
    final conflict = SyncConflict(
      noteId: 'same',
      local: local,
      pending: pending,
      remote: _remote('canonical-owner', deleted: true),
      detectedAt: _at,
    );
    final store = fixtures.MemoryStore(
      LocalSyncState(
        accountUserId: 'acct',
        notes: [local],
        outbox: [pending],
        conflicts: [conflict],
      ),
    );
    await expectLater(
      SyncConflictResolver(
        localSyncStore: store,
        generateNoteId: () => 'clone',
        generateMutationId: () => 'new',
        now: () => _at,
      ).resolve(
        accountUserId: 'acct',
        conflict: conflict,
        choice: SyncConflictChoice.useLocal,
      ),
      throwsA(isA<NoteSecurityFailure>()),
    );
    expect(store.state.outbox.single.mutationId, pending.mutationId);
    expect(store.state.notes.single.identity, local.identity);
  });
}
