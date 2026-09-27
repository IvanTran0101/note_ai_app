import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/note_sync_status.dart';

final DateTime _createdAt = DateTime.utc(2026, 9, 25, 9);
final DateTime _updatedAt = DateTime.utc(2026, 9, 25, 10);

LocalNoteState _note({
  String id = 'note-1',
  String ownerId = 'user-1',
  String title = 'Title',
  int serverRevision = 0,
  DateTime? deletedAt,
  NoteSyncStatus status = NoteSyncStatus.synced,
}) {
  return LocalNoteState(
    id: id,
    ownerId: ownerId,
    title: title,
    content: 'Content',
    createdAt: _createdAt,
    updatedAt: _updatedAt,
    serverRevision: serverRevision,
    deletedAt: deletedAt,
    status: status,
  );
}

void main() {
  test('accepts a just-created note and rejects invalid identity', () {
    final LocalNoteState local = _note();

    expect(local.serverRevision, 0);
    expect(local.status, NoteSyncStatus.synced);
    expect(() => _note(id: ' '), throwsArgumentError);
    expect(() => _note(ownerId: ''), throwsArgumentError);
    expect(() => _note(serverRevision: -1), throwsArgumentError);
  });

  test('a local tombstone is deletedAt, not an absent note', () {
    expect(_note().isDeleted, isFalse);
    expect(_note(deletedAt: _updatedAt).isDeleted, isTrue);
  });

  test('value equality covers the sync bookkeeping', () {
    expect(_note(), _note());
    expect(_note().hashCode, _note().hashCode);
    expect(_note(), isNot(_note(status: NoteSyncStatus.pending)));
    expect(_note(), isNot(_note(serverRevision: 2)));
    expect(_note(), isNot(_note(title: 'Other')));
    expect(_note(), isNot(_note(deletedAt: _updatedAt)));
  });
}
