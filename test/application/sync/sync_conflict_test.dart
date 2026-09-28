import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_conflict.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';

final DateTime _createdAt = DateTime.utc(2026, 9, 25, 9);
final DateTime _updatedAt = DateTime.utc(2026, 9, 25, 10);
const SyncNotePayload _payload = SyncNotePayload(
  title: 'Local title',
  content: 'Local content',
);

LocalNoteState _local({String id = 'note-1', int serverRevision = 1}) {
  return LocalNoteState(
    id: id,
    ownerId: 'user-1',
    title: 'Local title',
    content: 'Local content',
    createdAt: _createdAt,
    updatedAt: _updatedAt,
    serverRevision: serverRevision,
  );
}

PendingMutation _pending({String noteId = 'note-1'}) {
  return PendingMutation(
    mutationId: 'm-1',
    noteId: noteId,
    operation: SyncMutationOperation.update,
    baseRevision: 1,
    payload: _payload,
    createdAt: _updatedAt,
  );
}

SyncNoteSnapshot _remote({String id = 'note-1', DateTime? deletedAt}) {
  return SyncNoteSnapshot(
    id: id,
    title: 'Remote title',
    content: 'Remote content',
    createdAt: _createdAt,
    serverUpdatedAt: _updatedAt,
    revision: 2,
    deletedAt: deletedAt,
  );
}

void main() {
  test(
    'keeps the local loser, the rejected mutation, and the remote winner',
    () {
      final SyncConflict conflict = SyncConflict(
        noteId: 'note-1',
        remote: _remote(),
        local: _local(),
        pending: _pending(),
        detectedAt: _updatedAt,
      );

      expect(conflict.local.serverRevision, 1);
      expect(conflict.pending.mutationId, 'm-1');
      expect(conflict.remote?.revision, 2);
      expect(conflict.isRemoteDeleted, isFalse);
      expect(
        conflict,
        isNot(
          SyncConflict(
            noteId: 'note-1',
            remote: _remote(),
            local: _local(serverRevision: 5),
            pending: _pending(),
            detectedAt: _updatedAt,
          ),
        ),
      );
    },
  );

  test('distinguishes a remote tombstone from a missing remote note', () {
    final SyncConflict withoutRemote = SyncConflict(
      noteId: 'note-1',
      local: _local(),
      pending: _pending(),
      detectedAt: _updatedAt,
    );
    final SyncConflict withTombstone = SyncConflict(
      noteId: 'note-1',
      remote: _remote(deletedAt: _updatedAt),
      local: _local(),
      pending: _pending(),
      detectedAt: _updatedAt,
    );

    expect(withoutRemote.remote, isNull);
    expect(withoutRemote.isRemoteDeleted, isFalse);
    expect(withTombstone.remote, isNotNull);
    expect(withTombstone.isRemoteDeleted, isTrue);
    expect(withoutRemote, isNot(withTombstone));
  });

  test('refuses a conflict assembled from mismatched records', () {
    expect(
      () => SyncConflict(
        noteId: ' ',
        local: _local(),
        pending: _pending(),
        detectedAt: _updatedAt,
      ),
      throwsArgumentError,
    );
    expect(
      () => SyncConflict(
        noteId: 'note-2',
        local: _local(),
        pending: _pending(),
        detectedAt: _updatedAt,
      ),
      throwsArgumentError,
    );
    expect(
      () => SyncConflict(
        noteId: 'note-1',
        local: _local(),
        pending: _pending(noteId: 'note-2'),
        detectedAt: _updatedAt,
      ),
      throwsArgumentError,
    );
    expect(
      () => SyncConflict(
        noteId: 'note-1',
        remote: _remote(id: 'note-2'),
        local: _local(),
        pending: _pending(),
        detectedAt: _updatedAt,
      ),
      throwsArgumentError,
    );
  });

  test('compares by note, remote winner, local loser, and detection time', () {
    SyncConflict build({DateTime? detectedAt}) {
      return SyncConflict(
        noteId: 'note-1',
        remote: _remote(),
        local: _local(),
        pending: _pending(),
        detectedAt: detectedAt ?? _updatedAt,
      );
    }

    expect(build(), build());
    expect(build().hashCode, build().hashCode);
    expect(build(), isNot(build(detectedAt: _createdAt)));
  });
}
