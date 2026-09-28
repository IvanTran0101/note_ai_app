/// Codec for one persisted outbox entry (M2.0).
library;

import '../../application/sync/pending_mutation.dart';
import '../../application/sync/sync_failure.dart';
import '../../application/sync/sync_mutation.dart';
import 'local_sync_codec_reader.dart';
import 'local_sync_codec_schema.dart';

/// Maps a [PendingMutation] to and from one stored outbox record.
///
/// The record carries both the wire mutation and its attempt bookkeeping:
/// [PendingMutation.retryCount], [PendingMutation.lastError], and
/// [PendingMutation.blocked] are local state, so they are persisted next to the
/// mutation rather than rebuilt from it. The nested payload belongs to the same
/// record and is mapped here; a `delete` mutation stores an explicit null
/// payload, which is also the only operation allowed to omit one.
abstract final class PendingMutationCodec {
  /// Encodes [entry] as a JSON-compatible object.
  static Map<String, Object?> encode(PendingMutation entry) {
    final SyncNotePayload? payload = entry.payload;
    return <String, Object?>{
      LocalSyncSchema.mutationId: entry.mutationId,
      LocalSyncSchema.noteId: entry.noteId,
      LocalSyncSchema.operation: entry.operation.name,
      LocalSyncSchema.baseRevision: entry.baseRevision,
      LocalSyncSchema.payload: payload == null
          ? null
          : <String, Object?>{
              LocalSyncSchema.title: payload.title,
              LocalSyncSchema.content: payload.content,
            },
      LocalSyncSchema.createdAt: entry.createdAt.toIso8601String(),
      LocalSyncSchema.retryCount: entry.retryCount,
      LocalSyncSchema.lastError: entry.lastError?.name,
      LocalSyncSchema.blocked: entry.blocked,
    };
  }

  /// Decodes one standalone outbox record.
  static PendingMutation decode(Object? data, {String path = 'outbox entry'}) {
    return decodeRecord(
      SyncCodecObject.from(
        data,
        path: path,
        allowedFields: LocalSyncSchema.mutationFields,
      ),
    );
  }

  /// Decodes an outbox record already wrapped by the envelope or a conflict.
  static PendingMutation decodeRecord(SyncCodecObject record) {
    final String mutationId = record.requireNonBlankString(
      LocalSyncSchema.mutationId,
    );
    final String noteId = record.requireNonBlankString(LocalSyncSchema.noteId);
    final SyncMutationOperation operation = record.requireEnum(
      LocalSyncSchema.operation,
      SyncMutationOperation.values,
    );
    final int baseRevision = record.requireNonNegativeInt(
      LocalSyncSchema.baseRevision,
    );
    final SyncNotePayload? payload = _decodePayload(record);
    if (operation != SyncMutationOperation.delete && payload == null) {
      record.fail(
        LocalSyncSchema.payload,
        'is required for create and update.',
      );
    }
    final DateTime createdAt = record.requireTimestamp(
      LocalSyncSchema.createdAt,
    );
    final int retryCount = record.requireNonNegativeInt(
      LocalSyncSchema.retryCount,
    );
    final SyncErrorCode? lastError = record.requireNullableEnum(
      LocalSyncSchema.lastError,
      SyncErrorCode.values,
    );
    final bool blocked = record.requireBool(LocalSyncSchema.blocked);
    return buildCodecModel(
      () => PendingMutation(
        mutationId: mutationId,
        noteId: noteId,
        operation: operation,
        baseRevision: baseRevision,
        payload: payload,
        createdAt: createdAt,
        retryCount: retryCount,
        lastError: lastError,
        blocked: blocked,
      ),
      path: record.path,
    );
  }

  static SyncNotePayload? _decodePayload(SyncCodecObject record) {
    final SyncCodecObject? payload = record.requireNullableObject(
      LocalSyncSchema.payload,
      LocalSyncSchema.payloadFields,
    );
    if (payload == null) {
      return null;
    }
    return SyncNotePayload(
      title: payload.requireString(LocalSyncSchema.title),
      content: payload.requireString(LocalSyncSchema.content),
    );
  }
}
