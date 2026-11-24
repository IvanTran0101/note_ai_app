/// Shared builders for the M2 local sync codec tests.
///
/// The builders describe one fully populated account state and its individual
/// records, so each test can corrupt exactly one field and assert that the codec
/// rejects it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/note_sync_status.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_conflict.dart';
import 'package:note_ai_app/application/sync/sync_cursor.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_codec_exception.dart';

/// A timestamp with microsecond precision, so ISO-8601 round-tripping is real.
final DateTime fixtureCreatedAt = DateTime.utc(2026, 9, 25, 9, 0, 0, 123, 456);

/// A second timestamp, distinct from [fixtureCreatedAt].
final DateTime fixtureUpdatedAt = DateTime.utc(2026, 9, 25, 10, 30, 15);

/// The default payload title used by [mutationFixture].
const String fixturePayloadTitle = 'Payload title';

/// The default payload content used by [mutationFixture].
const String fixturePayloadContent = 'Payload content';

/// Values that must never appear in a codec failure message.
const String secretTitle = 'TOP-SECRET-TITLE';

/// A secret content value that must never appear in a failure message.
const String secretContent = 'TOP-SECRET-CONTENT';

/// A secret cursor value that must never appear in a failure message.
const String secretCursor = 'TOP-SECRET-CURSOR';

/// Builds one local note record.
LocalNoteState noteFixture({
  String id = 'note-1',
  String ownerId = 'user-1',
  String title = 'Note title',
  String content = 'Note content',
  DateTime? createdAt,
  DateTime? updatedAt,
  int serverRevision = 0,
  DateTime? deletedAt,
  NoteSyncStatus status = NoteSyncStatus.synced,
}) {
  return LocalNoteState(
    id: id,
    ownerId: ownerId,
    title: title,
    content: content,
    createdAt: createdAt ?? fixtureCreatedAt,
    updatedAt: updatedAt ?? fixtureUpdatedAt,
    serverRevision: serverRevision,
    deletedAt: deletedAt,
    status: status,
  );
}

/// Builds one outbox entry.
PendingMutation mutationFixture({
  String mutationId = 'mutation-1',
  String noteId = 'note-1',
  SyncMutationOperation operation = SyncMutationOperation.create,
  int baseRevision = 0,
  SyncNotePayload? payload = const SyncNotePayload(
    title: fixturePayloadTitle,
    content: fixturePayloadContent,
  ),
  DateTime? createdAt,
  int retryCount = 0,
  SyncErrorCode? lastError,
  bool blocked = false,
}) {
  return PendingMutation(
    mutationId: mutationId,
    noteId: noteId,
    operation: operation,
    baseRevision: baseRevision,
    payload: payload,
    createdAt: createdAt ?? fixtureUpdatedAt,
    retryCount: retryCount,
    lastError: lastError,
    blocked: blocked,
  );
}

/// Builds one remote snapshot; a non-null [deletedAt] makes it a tombstone.
SyncNoteSnapshot snapshotFixture({
  String id = 'note-1',
  String title = 'Remote title',
  String content = 'Remote content',
  DateTime? createdAt,
  DateTime? serverUpdatedAt,
  int revision = 2,
  DateTime? deletedAt,
}) {
  return SyncNoteSnapshot(
    id: id,
    title: title,
    content: content,
    createdAt: createdAt ?? fixtureCreatedAt,
    serverUpdatedAt: serverUpdatedAt ?? fixtureUpdatedAt,
    revision: revision,
    deletedAt: deletedAt,
  );
}

/// Builds one conflict; a null [remote] means the server withheld the note.
SyncConflict conflictFixture({
  String noteId = 'note-1',
  SyncNoteSnapshot? remote,
  LocalNoteState? local,
  PendingMutation? pending,
  DateTime? detectedAt,
}) {
  return SyncConflict(
    noteId: noteId,
    remote: remote,
    local: local ?? noteFixture(id: noteId),
    pending:
        pending ??
        mutationFixture(
          mutationId: 'mutation-$noteId',
          noteId: noteId,
          operation: SyncMutationOperation.update,
        ),
    detectedAt: detectedAt ?? fixtureUpdatedAt,
  );
}

/// A fully populated state: live notes, a tombstone, retry bookkeeping, all
/// three remote conflict shapes, and a cursor.
LocalSyncState richStateFixture() {
  return LocalSyncState(
    accountUserId: 'user-1',
    notes: <LocalNoteState>[
      noteFixture(),
      noteFixture(
        id: 'note-2',
        title: 'Second title',
        content: 'Second content',
        serverRevision: 3,
        status: NoteSyncStatus.pending,
      ),
      noteFixture(
        id: 'note-3',
        serverRevision: 4,
        deletedAt: fixtureUpdatedAt,
        status: NoteSyncStatus.conflict,
      ),
    ],
    outbox: <PendingMutation>[
      mutationFixture(),
      mutationFixture(
        mutationId: 'mutation-2',
        noteId: 'note-2',
        operation: SyncMutationOperation.update,
        baseRevision: 3,
        retryCount: 2,
        lastError: SyncErrorCode.throttled,
        blocked: true,
      ),
      mutationFixture(
        mutationId: 'mutation-3',
        noteId: 'note-3',
        operation: SyncMutationOperation.delete,
        baseRevision: 4,
        payload: null,
      ),
    ],
    conflicts: <SyncConflict>[
      conflictFixture(
        noteId: 'note-2',
        remote: snapshotFixture(id: 'note-2', revision: 5),
      ),
      conflictFixture(noteId: 'note-1', remote: null),
      conflictFixture(
        noteId: 'note-3',
        remote: snapshotFixture(
          id: 'note-3',
          revision: 6,
          deletedAt: fixtureUpdatedAt,
        ),
      ),
    ],
    cursor: const SyncCursor('opaque-cursor-1'),
  );
}

/// A minimal state with one live note and one queued mutation.
LocalSyncState simpleStateFixture({SyncCursor? cursor}) {
  return LocalSyncState(
    accountUserId: 'user-1',
    notes: <LocalNoteState>[noteFixture()],
    outbox: <PendingMutation>[mutationFixture()],
    cursor: cursor,
  );
}

/// Runs [action] and returns the typed codec failure it must raise.
LocalSyncCodecException codecFailure(void Function() action) {
  try {
    action();
  } on LocalSyncCodecException catch (error) {
    return error;
  }
  fail('expected a LocalSyncCodecException');
}

/// Returns a mutable copy of one decoded record, so a test can corrupt a field.
Map<String, Object?> copyRecord(Object? record) {
  return Map<String, Object?>.of(record! as Map<String, Object?>);
}
