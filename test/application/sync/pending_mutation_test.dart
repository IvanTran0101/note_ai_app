import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';

final DateTime _createdAt = DateTime.utc(2026, 9, 25, 11);
const SyncNotePayload _payload = SyncNotePayload(
  title: 'Title',
  content: 'Content',
);

PendingMutation _entry({
  String mutationId = 'm-1',
  SyncMutationOperation operation = SyncMutationOperation.create,
  int baseRevision = 0,
  SyncNotePayload? payload = _payload,
  int retryCount = 0,
  SyncErrorCode? lastError,
  bool blocked = false,
}) {
  return PendingMutation(
    mutationId: mutationId,
    noteId: 'note-1',
    operation: operation,
    baseRevision: baseRevision,
    payload: payload,
    createdAt: _createdAt,
    retryCount: retryCount,
    lastError: lastError,
    blocked: blocked,
  );
}

void main() {
  test('inherits the frozen SyncMutation payload semantics', () {
    expect(() => _entry(payload: null), throwsArgumentError);
    expect(
      () => _entry(
        operation: SyncMutationOperation.update,
        baseRevision: 1,
        payload: null,
      ),
      throwsArgumentError,
    );

    final PendingMutation deletion = _entry(
      operation: SyncMutationOperation.delete,
      baseRevision: 1,
      payload: null,
    );
    expect(deletion.payload, isNull);
    expect(deletion.operation, SyncMutationOperation.delete);
  });

  test('rejects invalid identity and a negative retry count', () {
    expect(() => _entry(mutationId: ' '), throwsArgumentError);
    expect(() => _entry(baseRevision: -1), throwsArgumentError);
    expect(_entry().retryCount, 0);
    expect(() => _entry(retryCount: -1), throwsArgumentError);
  });

  test('keeps a stable mutation id across retries', () {
    final PendingMutation entry = _entry(
      retryCount: 3,
      lastError: SyncErrorCode.timeout,
      blocked: true,
    );

    expect(entry.mutationId, 'm-1');
    expect(entry.toMutation(), _entry().toMutation());
    expect(
      entry.toMutation(),
      SyncMutation(
        mutationId: 'm-1',
        noteId: 'note-1',
        operation: SyncMutationOperation.create,
        baseRevision: 0,
        payload: _payload,
      ),
    );
  });

  test('defaults to an unblocked entry and compares attempt bookkeeping', () {
    final PendingMutation entry = _entry();

    expect(entry.blocked, isFalse);
    expect(entry.lastError, isNull);
    expect(entry, _entry());
    expect(entry.hashCode, _entry().hashCode);
    expect(entry, isNot(_entry(blocked: true)));
    expect(entry, isNot(_entry(retryCount: 1)));
    expect(entry, isNot(_entry(lastError: SyncErrorCode.networkUnavailable)));
  });
}
