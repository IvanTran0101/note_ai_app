import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/application/sync/sync_state_reconciliation.dart';
import 'package:note_ai_app/domain/labels/label_projection.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_role.dart';
import 'package:note_ai_app/domain/notes/note_share_grant.dart';

import '../../infrastructure/notes/note_repository_test_support.dart';

void main() {
  for (final role in NoteRole.values) {
    test('new shared labels preserve ${role.name} pending draft', () async {
      final fixture = _fixture(role);
      await _apply(fixture.store, fixture.local, 8);
      final updated = fixture.store.state.notes.single;
      expect(updated.labelIds, ['current']);
      expect(updated.labelProjections.single.name, 'Current');
      expect(updated.title, fixture.local.title);
      expect(updated.content, fixture.local.content);
      expect(updated.serverRevision, fixture.local.serverRevision);
      expect(fixture.store.state.outbox.single, same(fixture.pending));
      expect(
        fixture.store.state.outbox.single.blocked,
        role == NoteRole.viewer,
      );
    });
  }
  test('older shared label snapshot cannot replace current metadata', () async {
    final fixture = _fixture(NoteRole.viewer);
    await _apply(fixture.store, fixture.local, 6);
    expect(fixture.store.state.notes.single.labelIds, ['previous']);
    expect(fixture.store.state.outbox.single, same(fixture.pending));
  });
}

final _at = DateTime.utc(2026, 10, 5);

({LocalNoteState local, PendingMutation pending, FakeLocalSyncStore store})
_fixture(NoteRole role) {
  final local = LocalNoteState(
    id: 'n',
    ownerId: 'owner',
    share: NoteShareGrant(
      note: NoteIdentity('owner', 'n'),
      recipientId: 'recipient',
      role: role,
      sharedAt: _at,
      updatedAt: _at,
      accessRevision: 3,
    ),
    title: role == NoteRole.editor ? 'Current draft' : 'Cloud',
    content: role == NoteRole.editor ? 'Unsaved cloud draft' : 'Cloud body',
    createdAt: _at,
    updatedAt: _at,
    serverRevision: 7,
    labelIds: ['previous'],
    labelProjections: [LabelProjection(id: 'previous', name: 'Previous')],
  );
  final pending = _pending(role);
  final store = FakeLocalSyncStore(
    accountUserId: 'recipient',
    initial: LocalSyncState(
      accountUserId: 'recipient',
      notes: [local],
      outbox: [pending],
    ),
  );
  return (local: local, pending: pending, store: store);
}

PendingMutation _pending(NoteRole role) => PendingMutation(
  mutationId: role == NoteRole.viewer ? 'old-grant' : 'current-grant',
  noteId: 'n',
  ownerId: 'owner',
  accessRevision: role == NoteRole.viewer ? 1 : 3,
  operation: SyncMutationOperation.update,
  baseRevision: 7,
  payload: const SyncNotePayload(title: 'Draft', content: 'Retain encrypted'),
  createdAt: _at,
  retryCount: 3,
  blocked: role == NoteRole.viewer,
  lastError: role == NoteRole.viewer ? SyncErrorCode.forbidden : null,
);

Future<void> _apply(
  FakeLocalSyncStore store,
  LocalNoteState local,
  int revision,
) async {
  final reconciliation = SyncStateReconciliation(
    accountUserId: 'recipient',
    localStore: store,
    clock: () => _at,
  );
  await reconciliation.applyPage(
    SyncChangesPage(
      wireVersion: 2,
      snapshots: [
        SyncNoteSnapshot(
          id: 'n',
          ownerId: 'owner',
          share: local.share,
          title: 'Cloud',
          content: 'Cloud body',
          createdAt: _at,
          serverUpdatedAt: _at,
          revision: revision,
          includesLabels: true,
          labelIds: ['current'],
          labelProjections: [LabelProjection(id: 'current', name: 'Current')],
        ),
      ],
    ),
    expectedCursor: null,
  );
}
