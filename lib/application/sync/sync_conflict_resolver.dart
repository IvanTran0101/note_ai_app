/// Explicit application policy for resolving one stored sync conflict.
library;

import 'local_note_state.dart';
import 'local_sync_state.dart';
import 'local_sync_store.dart';
import 'note_sync_status.dart';
import 'pending_mutation.dart';
import 'sync_conflict.dart';
import 'sync_mutation.dart';
import 'sync_snapshot.dart';

enum SyncConflictChoice { useLocal, useRemote, later }

final class SyncConflictResolver {
  SyncConflictResolver({
    required this.localSyncStore,
    required this.generateNoteId,
    required this.generateMutationId,
    required this.now,
  });

  final ILocalSyncStore localSyncStore;
  final String Function() generateNoteId;
  final String Function() generateMutationId;
  final DateTime Function() now;

  Future<void> resolve({
    required String accountUserId,
    required SyncConflict conflict,
    required SyncConflictChoice choice,
  }) async {
    if (choice == SyncConflictChoice.later) return;
    await localSyncStore.update((LocalSyncState current) {
      if (current.accountUserId != accountUserId) {
        throw StateError(
          'The local sync store returned another account state.',
        );
      }
      final int conflictIndex = current.conflicts.indexOf(conflict);
      if (conflictIndex == -1) {
        throw StateError('The conflict is no longer stored for this account.');
      }
      final LocalNoteState? local = _findNote(current, conflict.noteId);
      if (local == null || local.ownerId != accountUserId) {
        throw StateError(
          'The conflict note is no longer owned by this account.',
        );
      }

      final List<LocalNoteState> notes = current.notes
          .where((LocalNoteState note) => note.id != local.id)
          .toList();
      final List<PendingMutation> outbox = current.outbox
          .where((PendingMutation item) => item.noteId != local.id)
          .toList();
      final DateTime timestamp = now();
      final SyncNoteSnapshot? remote = conflict.remote;

      if (choice == SyncConflictChoice.useRemote) {
        if (remote != null) notes.add(_fromRemote(remote, accountUserId));
      } else if (remote == null) {
        if (!local.isDeleted) {
          notes.add(_pendingNote(local, serverRevision: 0));
          outbox.add(
            _mutation(
              id: local.id,
              operation: SyncMutationOperation.create,
              baseRevision: 0,
              local: local,
              timestamp: timestamp,
            ),
          );
        }
      } else if (local.isDeleted) {
        if (remote.isDeleted) {
          notes.add(_fromRemote(remote, accountUserId));
        } else {
          notes.add(_pendingNote(local, serverRevision: remote.revision));
          outbox.add(
            _mutation(
              id: local.id,
              operation: SyncMutationOperation.delete,
              baseRevision: remote.revision,
              local: local,
              timestamp: timestamp,
            ),
          );
        }
      } else if (remote.isDeleted) {
        final LocalNoteState replacement = LocalNoteState(
          id: generateNoteId(),
          ownerId: accountUserId,
          title: local.title,
          content: local.content,
          createdAt: local.createdAt,
          updatedAt: timestamp,
          pinnedAt: local.pinnedAt,
          status: NoteSyncStatus.pending,
        );
        notes
          ..add(_fromRemote(remote, accountUserId))
          ..add(replacement);
        outbox.add(
          _mutation(
            id: replacement.id,
            operation: SyncMutationOperation.create,
            baseRevision: 0,
            local: replacement,
            timestamp: timestamp,
          ),
        );
      } else {
        notes.add(_pendingNote(local, serverRevision: remote.revision));
        outbox.add(
          _mutation(
            id: local.id,
            operation: SyncMutationOperation.update,
            baseRevision: remote.revision,
            local: local,
            timestamp: timestamp,
          ),
        );
      }

      final List<SyncConflict> conflicts = current.conflicts.toList()
        ..removeAt(conflictIndex);
      return LocalSyncState(
        accountUserId: current.accountUserId,
        notes: notes,
        outbox: outbox,
        conflicts: conflicts,
        cursor: current.cursor,
        userPreferences: current.userPreferences,
      );
    });
  }

  PendingMutation _mutation({
    required String id,
    required SyncMutationOperation operation,
    required int baseRevision,
    required LocalNoteState local,
    required DateTime timestamp,
  }) => PendingMutation(
    mutationId: generateMutationId(),
    noteId: id,
    operation: operation,
    baseRevision: baseRevision,
    payload: operation == SyncMutationOperation.delete
        ? null
        : SyncNotePayload(
            title: local.title,
            content: local.content,
            pinnedAt: local.pinnedAt,
            includesPinnedAt: true,
          ),
    createdAt: timestamp,
  );
}

LocalNoteState? _findNote(LocalSyncState state, String id) {
  for (final LocalNoteState note in state.notes) {
    if (note.id == id) return note;
  }
  return null;
}

LocalNoteState _pendingNote(
  LocalNoteState note, {
  required int serverRevision,
}) => LocalNoteState(
  id: note.id,
  ownerId: note.ownerId,
  title: note.title,
  content: note.content,
  createdAt: note.createdAt,
  updatedAt: note.updatedAt,
  pinnedAt: note.pinnedAt,
  serverRevision: serverRevision,
  deletedAt: note.deletedAt,
  status: NoteSyncStatus.pending,
);

LocalNoteState _fromRemote(SyncNoteSnapshot note, String accountUserId) =>
    LocalNoteState(
      id: note.id,
      ownerId: accountUserId,
      title: note.title,
      content: note.content,
      createdAt: note.createdAt,
      updatedAt: note.serverUpdatedAt,
      pinnedAt: note.pinnedAt,
      serverRevision: note.revision,
      deletedAt: note.deletedAt,
      status: NoteSyncStatus.synced,
    );
