import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/note_sync_status.dart';
import 'package:note_ai_app/application/sync/sync_conflict.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/infrastructure/sync/local_note_state_codec.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_codec_exception.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_codec_schema.dart';
import 'package:note_ai_app/infrastructure/sync/pending_mutation_codec.dart';
import 'package:note_ai_app/infrastructure/sync/sync_conflict_codec.dart';
import 'package:note_ai_app/infrastructure/sync/sync_note_snapshot_codec.dart';

import 'local_sync_codec_fixtures.dart';

void main() {
  group('conflict round trip', () {
    test('decodes a conflict with a live remote snapshot', () {
      final SyncConflict conflict = conflictFixture(
        remote: snapshotFixture(revision: 8),
      );

      final Map<String, Object?> record = SyncConflictCodec.encode(conflict);
      final SyncConflict decoded = SyncConflictCodec.decode(record);

      expect(decoded, conflict);
      expect(record.keys.toSet(), LocalSyncSchema.conflictFields);
      expect(decoded.isRemoteDeleted, isFalse);
      expect(decoded.noteId, 'note-1');
      expect(decoded.local, conflict.local);
      expect(decoded.pending, conflict.pending);
      expect(decoded.detectedAt, fixtureUpdatedAt);
    });

    test('decodes a conflict whose remote snapshot was withheld', () {
      final SyncConflict conflict = conflictFixture(remote: null);

      final Map<String, Object?> record = SyncConflictCodec.encode(conflict);
      final SyncConflict decoded = SyncConflictCodec.decode(record);

      expect(record.containsKey('remote'), isTrue);
      expect(record['remote'], isNull);
      expect(decoded, conflict);
      expect(decoded.remote, isNull);
      expect(decoded.isRemoteDeleted, isFalse);
    });

    test('keeps a remote tombstone distinct from a withheld snapshot', () {
      final SyncConflict conflict = conflictFixture(
        remote: snapshotFixture(revision: 9, deletedAt: fixtureUpdatedAt),
      );

      final SyncConflict decoded = SyncConflictCodec.decode(
        SyncConflictCodec.encode(conflict),
      );

      expect(decoded, conflict);
      expect(decoded.remote, isNotNull);
      expect(decoded.isRemoteDeleted, isTrue);
      expect(decoded.remote!.deletedAt, fixtureUpdatedAt);
    });

    test(
      'round-trips the local note, the rejected mutation, and its retries',
      () {
        final SyncConflict conflict = conflictFixture(
          remote: snapshotFixture(),
          local: noteFixture(
            serverRevision: 3,
            status: NoteSyncStatus.conflict,
          ),
          pending: mutationFixture(
            operation: SyncMutationOperation.update,
            baseRevision: 4,
            retryCount: 1,
            blocked: true,
          ),
        );

        final SyncConflict decoded = SyncConflictCodec.decode(
          SyncConflictCodec.encode(conflict),
        );

        expect(decoded, conflict);
        expect(decoded.local.serverRevision, 3);
        expect(decoded.pending.blocked, isTrue);
        expect(decoded.pending.operation, SyncMutationOperation.update);
      },
    );
  });

  group('remote snapshot record', () {
    test('round-trips a live and a deleted snapshot', () {
      final SyncNoteSnapshot live = snapshotFixture();
      final Map<String, Object?> record = SyncNoteSnapshotCodec.encode(live);

      expect(record.keys.toSet(), {
        ...LocalSyncSchema.snapshotFields.difference({'document'}),
        'includesAttachments',
        'includesLabels',
      });
      expect(record['serverUpdatedAt'], fixtureUpdatedAt.toIso8601String());
      expect(record['deletedAt'], isNull);
      expect(SyncNoteSnapshotCodec.decode(record), live);

      final SyncNoteSnapshot deleted = snapshotFixture(
        deletedAt: fixtureUpdatedAt,
      );
      expect(
        SyncNoteSnapshotCodec.decode(SyncNoteSnapshotCodec.encode(deleted)),
        deleted,
      );
    });

    test('rejects a non-positive revision and a bad server timestamp', () {
      final Map<String, Object?> badRevision = SyncNoteSnapshotCodec.encode(
        snapshotFixture(),
      )..['revision'] = 0;
      expect(
        codecFailure(() => SyncNoteSnapshotCodec.decode(badRevision)).message,
        'must be positive.',
      );

      final Map<String, Object?> badTimestamp = SyncNoteSnapshotCodec.encode(
        snapshotFixture(),
      )..['serverUpdatedAt'] = 'whenever';
      final LocalSyncCodecException error = codecFailure(
        () => SyncNoteSnapshotCodec.decode(badTimestamp),
      );
      expect(error.message, 'must be a valid ISO-8601 timestamp.');
      expect(error.path, 'remote note.serverUpdatedAt');
    });
  });

  group('strict conflict validation', () {
    test('rejects a local note that describes another note', () {
      final Map<String, Object?> record = SyncConflictCodec.encode(
        conflictFixture(remote: snapshotFixture()),
      );
      record['local'] = LocalNoteStateCodec.encode(noteFixture(id: 'note-2'));

      final LocalSyncCodecException error = codecFailure(
        () => SyncConflictCodec.decode(record),
      );

      expect(error.message, 'must match the conflict note id.');
      expect(error.path, 'conflict.local.id');
    });

    test('rejects a pending mutation that changes another note', () {
      final Map<String, Object?> record = SyncConflictCodec.encode(
        conflictFixture(remote: snapshotFixture()),
      );
      record['pending'] = PendingMutationCodec.encode(
        mutationFixture(mutationId: 'mutation-note-2', noteId: 'note-2'),
      );

      final LocalSyncCodecException error = codecFailure(
        () => SyncConflictCodec.decode(record),
      );

      expect(error.message, 'must match the conflict note id.');
      expect(error.path, 'conflict.pending.noteId');
    });

    test('rejects a remote snapshot that describes another note', () {
      final Map<String, Object?> record = SyncConflictCodec.encode(
        conflictFixture(remote: snapshotFixture()),
      );
      record['remote'] = SyncNoteSnapshotCodec.encode(
        snapshotFixture(id: 'note-2'),
      );

      final LocalSyncCodecException error = codecFailure(
        () => SyncConflictCodec.decode(record),
      );

      expect(error.message, 'must match the conflict note id.');
      expect(error.path, 'conflict.remote.id');
    });

    test('rejects a missing side of the conflict', () {
      for (final String field in <String>[
        'noteId',
        'remote',
        'local',
        'pending',
        'detectedAt',
      ]) {
        final Map<String, Object?> record = SyncConflictCodec.encode(
          conflictFixture(remote: snapshotFixture()),
        )..remove(field);

        final LocalSyncCodecException error = codecFailure(
          () => SyncConflictCodec.decode(record),
        );

        expect(error.message, 'must contain the field "$field".');
        expect(error.path, 'conflict');
      }
    });

    test('rejects an unknown nested field', () {
      final Map<String, Object?> record = SyncConflictCodec.encode(
        conflictFixture(remote: snapshotFixture()),
      );
      record['local'] = <String, Object?>{
        ...copyRecord(record['local']),
        'serverId': 'note-1',
      };

      final LocalSyncCodecException error = codecFailure(
        () => SyncConflictCodec.decode(record),
      );

      expect(error.message, contains('outside the M2 local sync schema'));
      expect(error.path, 'conflict.local');
    });

    test('rejects a remote that is neither null nor a snapshot object', () {
      final Map<String, Object?> record = SyncConflictCodec.encode(
        conflictFixture(remote: snapshotFixture()),
      )..['remote'] = 'remote-note';

      final LocalSyncCodecException error = codecFailure(
        () => SyncConflictCodec.decode(record),
      );

      expect(error.message, 'must be an object.');
      expect(error.path, 'conflict.remote');
    });

    test('rejects an unparsable detection timestamp', () {
      final Map<String, Object?> record = SyncConflictCodec.encode(
        conflictFixture(remote: null),
      )..['detectedAt'] = 'today';

      final LocalSyncCodecException error = codecFailure(
        () => SyncConflictCodec.decode(record),
      );

      expect(error.path, 'conflict.detectedAt');
    });
  });

  test('never echoes conflict note text in a failure', () {
    final Map<String, Object?> record = SyncConflictCodec.encode(
      conflictFixture(
        remote: snapshotFixture(title: secretTitle, content: secretContent),
        local: noteFixture(title: secretTitle, content: secretContent),
      ),
    )..['detectedAt'] = 'never';

    final LocalSyncCodecException error = codecFailure(
      () => SyncConflictCodec.decode(record),
    );

    expect(error.toString(), isNot(contains(secretTitle)));
    expect(error.toString(), isNot(contains(secretContent)));
  });
}
