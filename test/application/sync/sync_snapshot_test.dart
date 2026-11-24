import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';

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
  test('a tombstone is represented by deletedAt', () {
    expect(_snapshot().isDeleted, isFalse);
    expect(_snapshot(deletedAt: _updatedAt).isDeleted, isTrue);
    expect(() => _snapshot(revision: 0), throwsArgumentError);
  });

  test('change page keeps cursor opaque and snapshots immutable', () {
    final source = <SyncNoteSnapshot>[_snapshot()];
    final page = SyncChangesPage(
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
      () =>
          SyncChangesPage(snapshots: const <SyncNoteSnapshot>[], hasMore: true),
      throwsArgumentError,
    );
  });
}
