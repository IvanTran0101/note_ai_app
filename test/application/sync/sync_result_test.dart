import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/sync_result.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';

final SyncNoteSnapshot _snapshot = SyncNoteSnapshot(
  id: 'note-1',
  title: 'Title',
  content: 'Content',
  createdAt: DateTime.utc(2026, 9, 24, 10),
  serverUpdatedAt: DateTime.utc(2026, 9, 24, 11),
  revision: 1,
);

void main() {
  test('mutation results distinguish applied and conflict', () {
    final applied = SyncMutationResult.applied(
      mutationId: 'm-1',
      note: _snapshot,
    );
    final conflict = SyncMutationResult.conflict(
      mutationId: 'm-1',
      remote: _snapshot,
    );

    expect(applied.isApplied, isTrue);
    expect(applied.note, _snapshot);
    expect(conflict.isConflict, isTrue);
    expect(conflict.conflictRemote, _snapshot);
    expect(
      SyncMutationResult.conflict(mutationId: 'm-2').conflictRemote,
      isNull,
    );
  });
}
