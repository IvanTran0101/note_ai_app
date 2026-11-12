import '../../domain/notes/note_role.dart';
import '../../domain/labels/label.dart';
import 'local_note_state.dart';
import 'local_sync_state.dart';
import 'note_sync_status.dart';
import 'pending_mutation.dart';
import 'sync_conflict.dart';
import 'sync_failure.dart';
import 'sync_snapshot.dart';

/// Applies access metadata before content revisions and pending-write filtering.
final class SyncPageProjection {
  SyncPageProjection(this.state, this.fromRemote)
    : notes = List.of(state.notes),
      outbox = List.of(state.outbox),
      conflicts = List.of(state.conflicts);
  final LocalSyncState state;
  final LocalNoteState Function(
    SyncNoteSnapshot,
    NoteSyncStatus, {
    LocalNoteState? previous,
  })
  fromRemote;
  final List<LocalNoteState> notes;
  final List<PendingMutation> outbox;
  final List<SyncConflict> conflicts;
  int pulled = 0;
  bool changed = false;

  void apply(SyncNoteSnapshot snapshot) {
    final identity = snapshot.identityFor(state.accountUserId);
    final index = notes.indexWhere((n) => n.identity == identity);
    final old = index < 0 ? null : notes[index];
    if ((snapshot.share?.accessRevision ?? 0) <
        (old?.share?.accessRevision ?? 0)) {
      return;
    }
    // Own pending password changes win over historical cloud metadata.
    if (identity.ownerId == state.accountUserId &&
        outbox.any(
          (m) =>
              !m.isLabel &&
              m.mutation.identityFor(state.accountUserId) == identity &&
              m.protectionChange != null,
        )) {
      _updateConflict(snapshot);
      return;
    }
    if (old != null && snapshot.protection.revision < old.protection.revision) {
      return;
    }
    final accessChanged = old != null && snapshot.share != old.share;
    final protectionChanged =
        old != null && snapshot.protection != old.protection;
    if (accessChanged || protectionChanged) {
      notes[index] = fromRemote(snapshot, NoteSyncStatus.synced, previous: old);
      if (identity.ownerId != state.accountUserId) _blockStaleWork(snapshot);
      pulled++;
      changed = true;
      return;
    }
    _refreshLabels(snapshot, old, index);
    _recordLegacyDocumentConflict(snapshot, index);
    if (_updateConflict(snapshot)) return;
    if (outbox.any(
      (m) =>
          !m.isLabel && m.mutation.identityFor(state.accountUserId) == identity,
    )) {
      return;
    }
    if (old != null &&
        snapshot.revision <= old.serverRevision &&
        !_backfillsDocument(snapshot, old)) {
      return;
    }
    final incoming = fromRemote(snapshot, NoteSyncStatus.synced, previous: old);
    if (index < 0) {
      notes.add(incoming);
    } else {
      notes[index] = incoming;
    }
    pulled++;
    changed = true;
  }

  void _refreshLabels(
    SyncNoteSnapshot snapshot,
    LocalNoteState? old,
    int index,
  ) {
    if (old == null ||
        !snapshot.includesLabels ||
        !snapshot.contentAvailable ||
        !old.contentAvailable ||
        (snapshot.revision != old.serverRevision &&
            (old.share == null || snapshot.revision < old.serverRevision)) ||
        snapshot.protection != old.protection ||
        snapshot.share != old.share) {
      return;
    }
    // Shared membership is server-owned metadata even while a text draft is
    // pending. Refresh it without changing the draft's content/base revision.
    final ids = old.share == null ? old.labelIds : snapshot.labelIds;
    final projections = snapshot.labelProjections;
    if (sameLabelIds(ids, old.labelIds) &&
        projections.length == old.labelProjections.length &&
        Iterable<int>.generate(projections.length)
            .every((i) => projections[i] == old.labelProjections[i])) {
      return;
    }
    notes[index] = LocalNoteState(
      id: old.id,
      ownerId: old.ownerId,
      title: old.title,
      content: old.content,
      document: old.document,
      createdAt: old.createdAt,
      updatedAt: old.updatedAt,
      pinnedAt: old.pinnedAt,
      attachments: old.attachments,
      deletedAt: old.deletedAt,
      serverRevision: old.serverRevision,
      status: old.status,
      protection: old.protection,
      contentAvailable: old.contentAvailable,
      share: old.share,
      labelIds: ids,
      labelProjections: projections,
    );
    pulled++;
    changed = true;
  }

  bool _updateConflict(SyncNoteSnapshot snapshot) {
    final identity = snapshot.identityFor(state.accountUserId);
    final index = conflicts.indexWhere((c) => c.identity == identity);
    if (index < 0) return false;
    final old = conflicts[index];
    final previous = old.remote;
    final backfill =
        previous != null &&
        !previous.includesDocument &&
        snapshot.includesDocument &&
        snapshot.revision == previous.revision &&
        snapshot.title == previous.title &&
        snapshot.content == previous.content &&
        snapshot.contentAvailable == previous.contentAvailable &&
        snapshot.protection == previous.protection &&
        snapshot.share == previous.share &&
        snapshot.deletedAt == previous.deletedAt;
    if (snapshot.revision > (previous?.revision ?? 0) || backfill) {
      conflicts[index] = SyncConflict(
        noteId: old.noteId,
        remote: snapshot,
        local: old.local,
        pending: old.pending,
        detectedAt: old.detectedAt,
      );
      changed = true;
    }
    return true;
  }

  void _recordLegacyDocumentConflict(SyncNoteSnapshot snapshot, int index) {
    if (index < 0 ||
        snapshot.document == null ||
        !snapshot.contentAvailable ||
        conflicts.any(
          (c) => c.identity == snapshot.identityFor(state.accountUserId),
        )) {
      return;
    }
    final local = notes[index];
    final pending = outbox
        .where(
          (m) =>
              !m.isLabel &&
              m.mutation.identityFor(state.accountUserId) == local.identity &&
              m.blocked &&
              m.lastError == SyncErrorCode.documentRequiresUpgrade &&
              m.payload?.includesDocument != true,
        )
        .firstOrNull;
    if (pending == null ||
        !local.contentAvailable ||
        snapshot.revision < local.serverRevision ||
        snapshot.share != local.share ||
        snapshot.protection != local.protection) {
      return;
    }
    conflicts.add(
      SyncConflict(
        noteId: local.id,
        local: local,
        pending: pending,
        remote: snapshot,
        detectedAt: pending.createdAt,
      ),
    );
    changed = true;
  }

  bool _backfillsDocument(SyncNoteSnapshot snapshot, LocalNoteState old) =>
      snapshot.revision == old.serverRevision &&
      snapshot.includesDocument &&
      snapshot.document != null &&
      old.document == null &&
      old.contentAvailable &&
      snapshot.contentAvailable &&
      snapshot.title == old.title &&
      snapshot.content == old.content &&
      snapshot.protection == old.protection &&
      snapshot.share == old.share &&
      snapshot.deletedAt == old.deletedAt;

  void _blockStaleWork(SyncNoteSnapshot snapshot) {
    final identity = snapshot.identityFor(state.accountUserId);
    for (var i = 0; i < outbox.length; i++) {
      final entry = outbox[i];
      if (entry.isLabel ||
          entry.mutation.identityFor(state.accountUserId) != identity ||
          entry.accessRevision == snapshot.share?.accessRevision &&
              snapshot.share?.isActive == true &&
              snapshot.share?.role == NoteRole.editor) {
        continue;
      }
      outbox[i] = PendingMutation(
        mutationId: entry.mutationId,
        noteId: entry.noteId,
        ownerId: entry.ownerId,
        accessRevision: entry.accessRevision,
        operation: entry.operation,
        baseRevision: entry.baseRevision,
        payload: entry.payload,
        protectionChange: entry.protectionChange,
        createdAt: entry.createdAt,
        retryCount: entry.retryCount,
        lastError: SyncErrorCode.forbidden,
        blocked: true,
      );
    }
    for (var i = 0; i < conflicts.length; i++) {
      final old = conflicts[i];
      if (old.identity != identity) continue;
      final pending =
          outbox
              .where((m) => m.mutationId == old.pending.mutationId)
              .firstOrNull ??
          old.pending;
      final local = fromRemote(snapshot, NoteSyncStatus.conflict);
      conflicts[i] = SyncConflict(
        noteId: old.noteId,
        remote: snapshot,
        local: local,
        pending: pending,
        detectedAt: old.detectedAt,
      );
    }
  }
}
