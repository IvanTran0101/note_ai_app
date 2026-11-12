import '../../domain/labels/label_membership.dart';
import '../sync/local_sync_state.dart';
import '../sync/pending_mutation.dart';
import '../sync/sync_mutation.dart';

/// Only proven tombstones can normalize a NEVER-sent request. Unknown IDs and
/// attempted request bytes remain intact; the local Note is never rewritten.
PendingMutation normalizeLabelDispatch(
  LocalSyncState state,
  PendingMutation m,
) {
  final payload = m.payload;
  if (m.isLabel || m.retryCount != 0 || payload?.includesLabels != true) {
    return m;
  }
  final deleted = state.labels
      .where(
        (l) => l.isDeleted && l.ownerId == (m.ownerId ?? state.accountUserId),
      )
      .map((l) => l.id)
      .toSet();
  final ids = payload!.labelIds.where((id) => !deleted.contains(id)).toList();
  if (ids.length == payload.labelIds.length) return m;
  return PendingMutation(
    mutationId: m.mutationId,
    noteId: m.noteId,
    operation: m.operation,
    baseRevision: m.baseRevision,
    ownerId: m.ownerId,
    accessRevision: m.accessRevision,
    protectionChange: m.protectionChange,
    createdAt: m.createdAt,
    blocked: m.blocked,
    lastError: m.lastError,
    payload: SyncNotePayload(
      title: payload.title,
      content: payload.content,
      document: payload.document,
      includesDocument: payload.includesDocument,
      pinnedAt: payload.pinnedAt,
      includesPinnedAt: payload.includesPinnedAt,
      attachmentManifest: payload.attachmentManifest,
      includesAttachments: payload.includesAttachments,
      includesLabels: true,
      labelMembership: LabelMembership(ids),
    ),
  );
}
