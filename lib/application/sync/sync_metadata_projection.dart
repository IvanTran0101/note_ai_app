import 'local_note_state.dart';
import 'local_sync_state.dart';
import 'pending_mutation.dart';
import 'sync_conflict.dart';
import 'sync_mutation.dart';
import 'sync_snapshot.dart';

/// The presentation cache never retains protected content, even while unlocked.
final class SyncMetadataProjection {
  static LocalSyncState state(LocalSyncState source) {
    final protectedIds = <String>{
      for (final n in source.notes)
        if (n.protection.enabled || !n.contentAvailable) n.identity.key,
      for (final c in source.conflicts)
        if (_privateConflict(c)) c.identity.key,
    };
    return LocalSyncState(
      accountUserId: source.accountUserId,
      userPreferences: source.userPreferences,
      cursor: source.cursor,
      notes: source.notes.map(
        (n) => _note(n, protectedIds.contains(n.identity.key)),
      ),
      outbox: source.outbox.map(
        (m) =>
            _pending(m, protectedIds.contains(m.keyFor(source.accountUserId))),
      ),
      conflicts: source.conflicts.map(conflict),
    );
  }

  static bool _privateConflict(SyncConflict c) =>
      c.local.protection.enabled ||
      !c.local.contentAvailable ||
      (c.remote?.protection.enabled ?? false) ||
      !(c.remote?.contentAvailable ?? true);

  static SyncConflict conflict(SyncConflict source) {
    final hide = _privateConflict(source);
    final remote = source.remote;
    return SyncConflict(
      noteId: source.noteId,
      detectedAt: source.detectedAt,
      local: _note(source.local, hide),
      pending: _pending(source.pending, hide),
      remote: remote == null || !hide
          ? remote
          : SyncNoteSnapshot(
              id: remote.id,
              pinnedAt: remote.pinnedAt,
              title: '',
              content: '',
              createdAt: remote.createdAt,
              serverUpdatedAt: remote.serverUpdatedAt,
              revision: remote.revision,
              deletedAt: remote.deletedAt,
              protection: remote.protection,
              ownerId: remote.ownerId,
              share: remote.share,
              contentAvailable: false,
            ),
    );
  }

  static LocalNoteState _note(LocalNoteState n, bool hide) => !hide
      ? n
      : LocalNoteState(
          id: n.id,
          pinnedAt: n.pinnedAt,
          ownerId: n.ownerId,
          title: '',
          content: '',
          createdAt: n.createdAt,
          updatedAt: n.updatedAt,
          serverRevision: n.serverRevision,
          deletedAt: n.deletedAt,
          status: n.status,
          protection: n.protection,
          share: n.share,
          contentAvailable: false,
        );

  static PendingMutation _pending(PendingMutation m, bool hide) => !hide
      ? m
      : PendingMutation(
          mutationId: m.mutationId,
          noteId: m.noteId,
          operation: m.operation,
          baseRevision: m.baseRevision,
          payload: m.payload == null
              ? null
              : const SyncNotePayload(title: '', content: ''),
          createdAt: m.createdAt,
          retryCount: m.retryCount,
          lastError: m.lastError,
          blocked: m.blocked,
          ownerId: m.ownerId,
          accessRevision: m.accessRevision,
          protectionChange: m.protectionChange,
        );
}
