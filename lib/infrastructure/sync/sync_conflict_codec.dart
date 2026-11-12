/// Codec for one persisted sync conflict record (M2.0).
library;

import '../../application/sync/local_note_state.dart';
import '../../application/sync/pending_mutation.dart';
import '../../application/sync/sync_conflict.dart';
import '../../application/sync/sync_snapshot.dart';
import 'local_note_state_codec.dart';
import 'local_sync_codec_reader.dart';
import 'local_sync_codec_schema.dart';
import 'pending_mutation_codec.dart';
import 'sync_note_snapshot_codec.dart';

/// Maps a [SyncConflict] to and from one stored record.
///
/// The record embeds all three sides of the conflict: the winning remote
/// snapshot (an explicit null when the server withheld it, and a snapshot with a
/// tombstone marker when the remote side was deleted), the local note that lost,
/// and the rejected pending mutation. The nested records must all describe the
/// same [SyncConflict.noteId]; the codec checks that with field paths, and the
/// model constructor repeats it as a backstop.
abstract final class SyncConflictCodec {
  /// Encodes [conflict] as a JSON-compatible object.
  static Map<String, Object?> encode(SyncConflict conflict) {
    final SyncNoteSnapshot? remote = conflict.remote;
    return <String, Object?>{
      LocalSyncSchema.noteId: conflict.noteId,
      LocalSyncSchema.remote: remote == null
          ? null
          : SyncNoteSnapshotCodec.encode(remote),
      LocalSyncSchema.local: LocalNoteStateCodec.encode(conflict.local),
      LocalSyncSchema.pending: PendingMutationCodec.encode(conflict.pending),
      LocalSyncSchema.detectedAt: conflict.detectedAt.toIso8601String(),
    };
  }

  /// Decodes one standalone conflict record.
  static SyncConflict decode(Object? data, {String path = 'conflict'}) {
    return decodeRecord(
      SyncCodecObject.from(
        data,
        path: path,
        allowedFields: LocalSyncSchema.conflictFields,
      ),
    );
  }

  /// Decodes a conflict record already wrapped by the envelope.
  static SyncConflict decodeRecord(SyncCodecObject record) {
    final String noteId = record.requireNonBlankString(LocalSyncSchema.noteId);
    final SyncCodecObject? remoteRecord = record.requireNullableObject(
      LocalSyncSchema.remote,
      LocalSyncSchema.snapshotFields,
      optionalFields: LocalSyncSchema.snapshotOptionalFields,
    );
    final SyncNoteSnapshot? remote = remoteRecord == null
        ? null
        : SyncNoteSnapshotCodec.decodeRecord(remoteRecord);
    final SyncCodecObject localRecord = record.requireObject(
      LocalSyncSchema.local,
      LocalSyncSchema.noteFields,
      optionalFields: LocalSyncSchema.noteOptionalFields,
    );
    final LocalNoteState local = LocalNoteStateCodec.decodeRecord(localRecord);
    final SyncCodecObject pendingRecord = record.requireObject(
      LocalSyncSchema.pending,
      LocalSyncSchema.mutationFields,
      optionalFields: LocalSyncSchema.mutationOptionalFields,
    );
    final PendingMutation pending = PendingMutationCodec.decodeRecord(
      pendingRecord,
    );
    final DateTime detectedAt = record.requireTimestamp(
      LocalSyncSchema.detectedAt,
    );

    if (local.id != noteId) {
      localRecord.fail(LocalSyncSchema.id, 'must match the conflict note id.');
    }
    if (pending.noteId != noteId) {
      pendingRecord.fail(
        LocalSyncSchema.noteId,
        'must match the conflict note id.',
      );
    }
    if (remote != null && remote.id != noteId) {
      remoteRecord!.fail(
        LocalSyncSchema.id,
        'must match the conflict note id.',
      );
    }
    return buildCodecModel(
      () => SyncConflict(
        noteId: noteId,
        remote: remote,
        local: local,
        pending: pending,
        detectedAt: detectedAt,
      ),
      path: record.path,
    );
  }
}
