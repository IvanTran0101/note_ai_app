import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';

void main() {
  test('requires payload for create and update, but not delete', () {
    const payload = SyncNotePayload(title: 'Title', content: 'Content');

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

    final deletion = SyncMutation(
      mutationId: 'm-1',
      noteId: 'n-1',
      operation: SyncMutationOperation.delete,
      baseRevision: 1,
    );
    final creation = SyncMutation(
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
}
