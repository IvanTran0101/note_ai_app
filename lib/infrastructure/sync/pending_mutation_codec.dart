/// Codec for one persisted outbox entry (M2.0).
library;

import '../../application/sync/pending_mutation.dart';
import '../../application/sync/sync_failure.dart';
import '../../application/sync/sync_mutation.dart';
import 'local_sync_codec_reader.dart';
import 'protection_sync_codec.dart';
import 'local_sync_codec_schema.dart';
import '../attachments/attachment_codec.dart';
import '../../domain/notes/attachment.dart';
import '../../domain/labels/label_membership.dart';
import '../labels/label_codec.dart';

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
      if (entry.isLabel) 'entityType': 'label',
      if (entry.mutation.labelName != null)
        'labelName': entry.mutation.labelName,
      if (entry.ownerId != null) LocalSyncSchema.ownerId: entry.ownerId,
      if (entry.accessRevision != null)
        LocalSyncSchema.accessRevision: entry.accessRevision,
      if (entry.protectionChange != null)
        'protectionChange': ProtectionSyncCodec.encode(entry.protectionChange!),
      LocalSyncSchema.operation: entry.operation.name,
      LocalSyncSchema.baseRevision: entry.baseRevision,
      LocalSyncSchema.payload: payload == null ? null : _encodePayload(payload),
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
        optionalFields: LocalSyncSchema.mutationOptionalFields,
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
    final isLabel =
        record.containsField('entityType') &&
        record.rawValue('entityType') == 'label';
    if (record.containsField('entityType') && !isLabel) {
      record.fail('entityType', 'Unsupported entity type.');
    }
    if (!isLabel &&
        operation != SyncMutationOperation.delete &&
        payload == null) {
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
        ownerId: !record.containsField(LocalSyncSchema.ownerId)
            ? null
            : record.requireNonBlankString(LocalSyncSchema.ownerId),
        accessRevision: !record.containsField(LocalSyncSchema.accessRevision)
            ? null
            : record.requirePositiveInt(LocalSyncSchema.accessRevision),
        protectionChange: record.containsField('protectionChange')
            ? ProtectionSyncCodec.decode(record.rawValue('protectionChange'))
            : null,
        operation: operation,
        baseRevision: baseRevision,
        payload: payload,
        entityType: isLabel ? SyncEntityType.label : SyncEntityType.note,
        labelName: record.containsField('labelName')
            ? record.requireString('labelName')
            : null,
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
      optionalFields: <String>{
        LocalSyncSchema.pinnedAt,
        LocalSyncSchema.attachments,
        'labelIds',
      },
    );
    if (payload == null) {
      return null;
    }
    return SyncNotePayload(
      title: payload.requireString(LocalSyncSchema.title),
      content: payload.requireString(LocalSyncSchema.content),
      labelMembership: payload.contains('labelIds')
          ? LabelMembership(LabelCodec.ids(payload.rawValue('labelIds')))
          : const LabelMembership.empty(),
      includesLabels: payload.contains('labelIds'),
      pinnedAt: payload.requireNullableTimestamp(LocalSyncSchema.pinnedAt),
      includesPinnedAt: payload.contains(LocalSyncSchema.pinnedAt),
      includesAttachments: payload.contains(LocalSyncSchema.attachments),
      attachmentManifest: payload.contains(LocalSyncSchema.attachments)
          ? AttachmentManifest(
              AttachmentCodec.decodeList(
                payload.rawValue(LocalSyncSchema.attachments),
                noteId: record.requireNonBlankString(LocalSyncSchema.noteId),
              ),
            )
          : const AttachmentManifest.empty(),
    );
  }

  static Map<String, Object?> _encodePayload(SyncNotePayload payload) =>
      <String, Object?>{
        LocalSyncSchema.title: payload.title,
        LocalSyncSchema.content: payload.content,
        if (payload.includesLabels) 'labelIds': payload.labelIds,
        if (payload.includesAttachments)
          LocalSyncSchema.attachments: payload.attachments
              .map(AttachmentCodec.encode)
              .toList(),
        if (payload.includesPinnedAt)
          LocalSyncSchema.pinnedAt: payload.pinnedAt?.toIso8601String(),
      };
}
