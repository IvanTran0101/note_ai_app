import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/sync_contract.dart';

final DateTime _createdAt = DateTime.utc(2026, 9, 24, 10);
final DateTime _updatedAt = DateTime.utc(2026, 9, 24, 11);

SyncNoteSnapshot _snapshot({int revision = 1, DateTime? deletedAt}) {
  return SyncNoteSnapshot(
    id: 'note-1',
    title: 'Title',
    content: 'Content',
    createdAt: _createdAt,
    serverUpdatedAt: _updatedAt,
    revision: revision,
    deletedAt: deletedAt,
  );
}

void main() {
  group('SyncMutation', () {
    test('requires payload for create and update, but not delete', () {
      const SyncNotePayload payload = SyncNotePayload(
        title: 'Title',
        content: 'Content',
      );

      expect(
        () => SyncMutation(
          mutationId: 'm-1',
          noteId: 'n-1',
          operation: SyncMutationOperation.create,
          baseRevision: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => SyncMutation(
          mutationId: 'm-1',
          noteId: 'n-1',
          operation: SyncMutationOperation.update,
          baseRevision: 1,
        ),
        throwsArgumentError,
      );

      final SyncMutation deletion = SyncMutation(
        mutationId: 'm-1',
        noteId: 'n-1',
        operation: SyncMutationOperation.delete,
        baseRevision: 1,
      );
      final SyncMutation creation = SyncMutation(
        mutationId: 'm-1',
        noteId: 'n-1',
        operation: SyncMutationOperation.create,
        baseRevision: 0,
        payload: payload,
      );

      expect(deletion.payload, isNull);
      expect(creation.payload, payload);
    });

    test('rejects blank ids and negative revisions', () {
      expect(
        () => SyncMutation(
          mutationId: ' ',
          noteId: 'n-1',
          operation: SyncMutationOperation.delete,
          baseRevision: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => SyncMutation(
          mutationId: 'm-1',
          noteId: 'n-1',
          operation: SyncMutationOperation.delete,
          baseRevision: -1,
        ),
        throwsArgumentError,
      );
    });
  });

  test('a tombstone is represented by deletedAt', () {
    expect(_snapshot().isDeleted, isFalse);
    expect(_snapshot(deletedAt: _updatedAt).isDeleted, isTrue);
    expect(() => _snapshot(revision: 0), throwsArgumentError);
  });

  test('mutation results distinguish applied and conflict', () {
    final SyncMutationResult applied = SyncMutationResult.applied(
      mutationId: 'm-1',
      note: _snapshot(),
    );
    final SyncMutationResult conflict = SyncMutationResult.conflict(
      mutationId: 'm-1',
      remote: _snapshot(revision: 2),
    );

    expect(applied.isApplied, isTrue);
    expect(applied.note, _snapshot());
    expect(conflict.isConflict, isTrue);
    expect(conflict.conflictRemote, _snapshot(revision: 2));
    expect(
      SyncMutationResult.conflict(mutationId: 'm-2').conflictRemote,
      isNull,
    );
  });

  test('change page keeps cursor opaque and snapshots immutable', () {
    final List<SyncNoteSnapshot> source = <SyncNoteSnapshot>[_snapshot()];
    final SyncChangesPage page = SyncChangesPage(
      snapshots: source,
      nextCursor: 'opaque-cursor',
      hasMore: true,
    );
    source.clear();

    expect(page.snapshots, hasLength(1));
    expect(page.nextCursor, 'opaque-cursor');
    expect(
      () => page.snapshots.add(_snapshot(revision: 2)),
      throwsUnsupportedError,
    );
    expect(
      SyncChangesPage(
        snapshots: <SyncNoteSnapshot>[_snapshot()],
        nextCursor: 'last-seen-cursor',
      ).hasMore,
      isFalse,
    );
    expect(
      () => SyncChangesPage(
        snapshots: const <SyncNoteSnapshot>[],
        nextCursor: null,
        hasMore: true,
      ),
      throwsArgumentError,
    );
  });

  test('classifies retryable and permanent failures', () {
    expect(const SyncFailure(code: SyncErrorCode.timeout).retryable, isTrue);
    expect(
      const SyncFailure(code: SyncErrorCode.unauthorized).retryable,
      isFalse,
    );
  });
}
