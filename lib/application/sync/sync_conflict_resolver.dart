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
import '../notes/note_access.dart';
import '../../domain/notes/note_protection.dart';

enum SyncConflictChoice { useLocal, useRemote, later }

final class SyncConflictResolver {
  SyncConflictResolver({
    required this.localSyncStore,
    required this.generateNoteId,
    required this.generateMutationId,
    required this.now,
    this.accessGuard,
  });

  final ILocalSyncStore localSyncStore;
  final String Function() generateNoteId;
  final String Function() generateMutationId;
  final DateTime Function() now;
  final INoteAccessGuard? accessGuard;

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
      if (local.protection.enabled) {
        final guard = accessGuard;
        if (guard == null ||
            !local.contentAvailable ||
            (choice == SyncConflictChoice.useRemote &&
                remote != null &&
                !remote.contentAvailable)) {
          throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
        }
        guard.requireAccess(
          ownerId: accountUserId,
          noteId: local.id,
          protection: local.protection,
          operation: local.isDeleted
              ? NoteOperation.delete
              : NoteOperation.edit,
        );
        // Copying a protected deleted note into another identity is export.
        if (choice == SyncConflictChoice.useLocal &&
            (remote == null || remote.isDeleted)) {
          guard.requireAccess(
            ownerId: accountUserId,
            noteId: local.id,
            protection: local.protection,
            operation: NoteOperation.export,
          );
        }
      }

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
        : SyncNotePayload(title: local.title, content: local.content),
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
  serverRevision: serverRevision,
  deletedAt: note.deletedAt,
  status: NoteSyncStatus.pending,
  protection: note.protection,
  contentAvailable: note.contentAvailable,
);

LocalNoteState _fromRemote(SyncNoteSnapshot note, String accountUserId) =>
    LocalNoteState(
      id: note.id,
      ownerId: accountUserId,
      title: note.title,
      content: note.content,
      createdAt: note.createdAt,
      updatedAt: note.serverUpdatedAt,
      serverRevision: note.revision,
      deletedAt: note.deletedAt,
      status: NoteSyncStatus.synced,
      protection: note.protection,
      contentAvailable: note.contentAvailable,
    );
