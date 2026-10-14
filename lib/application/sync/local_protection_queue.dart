import '../../domain/notes/attachment.dart';
import '../../domain/labels/label_membership.dart';
import '../notes/note_access.dart';
import 'local_note_state.dart';
import 'local_sync_state.dart';
import 'note_sync_status.dart';
import 'pending_mutation.dart';
import 'protection_sync_change.dart';
import 'sync_mutation.dart';

/// Uses the same content outbox. An attempted request is immutable.
abstract final class LocalProtectionQueue {
  static LocalSyncState apply(
    LocalSyncState state,
    LocalNoteState original,
    LocalSyncState sealed,
    ProtectionSyncChange change,
    String mutationId,
    DateTime timestamp,
  ) {
    final identity = original.identity;
    if (state.conflicts.any((c) => c.identity == identity)) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.pendingSync);
    }
    final entries = List<PendingMutation>.of(sealed.outbox);
    final index = entries.lastIndexWhere(
      (m) =>
          !m.isLabel && m.mutation.identityFor(state.accountUserId) == identity,
    );
    final last = index < 0 ? null : entries[index];
    if (last?.operation == SyncMutationOperation.delete) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
    }
    final note = sealed.notes.firstWhere((n) => n.identity == identity);
    final pending = _pending(
      original,
      note,
      last,
      change,
      mutationId,
      timestamp,
    );
    if (last != null && last.retryCount == 0 && !last.blocked) {
      entries[index] = pending;
    } else {
      entries.add(pending);
    }
    return LocalSyncState(
      accountUserId: state.accountUserId,
      labels: state.labels,
      syncWireVersion: state.syncWireVersion,
      userPreferences: state.userPreferences,
      notes: sealed.notes.map(
        (n) => n.identity != identity ? n : _markPending(n, timestamp),
      ),
      outbox: entries,
      conflicts: sealed.conflicts,
      cursor: sealed.cursor,
    );
  }

  static PendingMutation _pending(
    LocalNoteState original,
    LocalNoteState note,
    PendingMutation? last,
    ProtectionSyncChange change,
    String mutationId,
    DateTime timestamp,
  ) {
    final coalesce = last != null && last.retryCount == 0 && !last.blocked;
    final pending = PendingMutation(
      mutationId: coalesce ? last.mutationId : mutationId,
      noteId: original.id,
      ownerId: last?.ownerId,
      accessRevision: last?.accessRevision,
      operation: coalesce
          ? last.operation
          : original.serverRevision == 0 && last == null
          ? SyncMutationOperation.create
          : SyncMutationOperation.update,
      baseRevision: coalesce
          ? last.baseRevision
          : last == null
          ? original.serverRevision
          : last.baseRevision + 1,
      payload: SyncNotePayload(
        title: note.title,
        content: note.content,
        document: note.document,
        includesDocument: note.document != null,
        labelMembership: LabelMembership(note.labelIds),
        includesLabels:
            note.labelIds.isNotEmpty || last?.payload?.includesLabels == true,
        pinnedAt: note.pinnedAt,
        includesPinnedAt: true,
        attachmentManifest: AttachmentManifest(note.attachments),
        includesAttachments:
            note.attachments.isNotEmpty ||
            last?.payload?.includesAttachments == true,
      ),
      protectionChange: ProtectionSyncChange(
        before: coalesce
            ? last.protectionChange?.before ?? change.before
            : change.before,
        after: change.after,
        verifier: change.verifier,
      ),
      createdAt: coalesce ? last.createdAt : timestamp,
    );
    return pending;
  }

  static LocalNoteState _markPending(LocalNoteState n, DateTime timestamp) =>
      LocalNoteState(
        id: n.id,
        pinnedAt: n.pinnedAt,
        attachments: n.attachments,
        labelIds: n.labelIds,
        labelProjections: n.labelProjections,
        ownerId: n.ownerId,
        title: n.title,
        content: n.content,
        document: n.document,
        createdAt: n.createdAt,
        updatedAt: timestamp,
        serverRevision: n.serverRevision,
        deletedAt: n.deletedAt,
        protection: n.protection,
        share: n.share,
        contentAvailable: n.contentAvailable,
        status: NoteSyncStatus.pending,
      );
}
