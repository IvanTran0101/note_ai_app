import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/labels/local_label_state.dart';
import 'package:note_ai_app/application/labels/normalize_label_dispatch.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/domain/labels/label_membership.dart';

final time = DateTime.utc(2026, 10, 4);

void main() {
  final state = LocalSyncState(
    accountUserId: 'owner',
    labels: [
      LocalLabelState(
        id: 'gone',
        ownerId: 'owner',
        name: 'Removed',
        createdAt: time,
        updatedAt: time,
        deletedAt: time,
      ),
    ],
  );
  PendingMutation request({int attempts = 0, bool labels = true}) =>
      PendingMutation(
        mutationId: 'stable',
        noteId: 'n',
        operation: SyncMutationOperation.create,
        baseRevision: 0,
        createdAt: time,
        retryCount: attempts,
        payload: SyncNotePayload(
          title: 'Draft',
          content: 'Body',
          includesLabels: labels,
          includesPinnedAt: true,
          pinnedAt: time,
          labelMembership: LabelMembership(['gone', 'unknown']),
        ),
      );
  test('never-sent normalizes verified tombstone only, preserves identity pin/body and unknown', () {
    final m = normalizeLabelDispatch(state, request());
    expect(m.mutationId, 'stable');
    expect(m.retryCount, 0);
    expect(m.payload!.labelIds, ['unknown']);
    expect(m.payload!.title, 'Draft');
    expect(m.payload!.pinnedAt, time);
    expect(m.payload!.includesPinnedAt, true);
  });
  test('attempted request remains byte-for-byte/equality intact', () {
    final m = request(attempts: 1);
    expect(identical(normalizeLabelDispatch(state, m), m), true);
  });
  test('legacy omitted labels do not upgrade implicitly', () {
    final m = request(labels: false);
    expect(identical(normalizeLabelDispatch(state, m), m), true);
  });
}
