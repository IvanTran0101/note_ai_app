part of 'sync_http_mapper.dart';

bool requiresSyncWireV3(SyncMutation mutation) =>
    mutation.payload?.includesDocument == true;

bool requiresSyncWireV2(SyncMutation mutation) =>
    mutation.isLabel ||
    mutation.payload?.includesLabels == true ||
    mutation.payload?.includesAttachments == true;

/// Frozen legacy payloads stay byte-equivalent for idempotent retries.
/// A typed document is sent only by the explicit V3 protocol.
Map<String, Object?> encodeSyncMutation(SyncMutation mutation) {
  if (mutation.isLabel) {
    return {
      'wireVersion': 2,
      'entityType': 'label',
      'mutationId': mutation.mutationId,
      'labelId': mutation.noteId,
      'operation': mutation.operation.name,
      'baseRevision': mutation.baseRevision,
      if (mutation.labelName != null) 'payload': {'name': mutation.labelName},
    };
  }
  final typedDocument = requiresSyncWireV3(mutation);
  final body = <String, Object?>{
    if (typedDocument || requiresSyncWireV2(mutation)) ...{
      'wireVersion': typedDocument ? 3 : 2,
      'entityType': 'note',
      if (typedDocument) 'documentCapability': 'basicBlocksV1',
    },
    'mutationId': mutation.mutationId,
    'noteId': mutation.noteId,
    'operation': mutation.operation.name,
    'baseRevision': mutation.baseRevision,
    if (mutation.ownerId != null) 'ownerId': mutation.ownerId,
    if (mutation.accessRevision != null)
      'accessRevision': mutation.accessRevision,
    if (mutation.protectionChange != null)
      'protectionChange': ProtectionSyncCodec.encode(
        mutation.protectionChange!,
      ),
  };
  final payload = mutation.payload;
  if (payload != null) {
    body['payload'] = {
      'title': payload.title,
      'content': payload.content,
      if (typedDocument)
        'document': payload.document == null
            ? null
            : NoteDocumentCodec.encode(payload.document!),
      if (payload.includesLabels) 'labelIds': payload.labelIds,
      if (payload.includesAttachments)
        'attachments': payload.attachments.map(AttachmentCodec.encode).toList(),
      if (payload.includesPinnedAt)
        'pinnedAt': payload.pinnedAt?.toIso8601String(),
    };
  }
  return body;
}

String syncMutationPath(SyncMutation mutation) {
  final prefix = requiresSyncWireV3(mutation)
      ? 'sync/v3/'
      : requiresSyncWireV2(mutation)
      ? 'sync/v2/'
      : 'sync/';
  final route = mutation.ownerId != null
      ? 'shared-mutations'
      : mutation.protectionChange != null
      ? 'protected-mutations'
      : 'mutations';
  return '$prefix$route';
}
