/// Explicit application policy for resolving one stored sync conflict.
library;

import '../../domain/notes/attachment.dart';
import '../../domain/labels/label_membership.dart';

import 'local_note_state.dart';
import 'local_sync_state.dart';
import 'local_sync_store.dart';
import 'note_sync_status.dart';
import 'pending_mutation.dart';
import 'sync_conflict.dart';
import 'sync_mutation.dart';
import 'protection_sync_change.dart';
import 'sync_snapshot.dart';
import '../notes/note_access.dart';
import '../../domain/notes/note_protection.dart';
import '../../domain/notes/note_access_policy.dart';
import '../../domain/notes/note_identity.dart';

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
      final LocalNoteState? local = _findNote(current, conflict.identity);
      if (local == null) {
        throw StateError(
          'The conflict note is no longer available in this account.',
        );
      }

      final operation = choice == SyncConflictChoice.useRemote
          ? NoteOperation.read
          : local.isDeleted
          ? NoteOperation.delete
          : NoteOperation.edit;
      if (!const NoteAccessPolicy().allows(
            actorId: accountUserId,
            note: local.identity,
            share: local.share,
            operation: operation,
          ) ||
          local.ownerId != accountUserId &&
              choice == SyncConflictChoice.useLocal &&
              (conflict.remote == null ||
                  conflict.remote!.isDeleted ||
                  local.isDeleted)) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
      }
      final List<LocalNoteState> notes = current.notes
          .where((LocalNoteState note) => note.identity != local.identity)
          .toList();
      final List<PendingMutation> outbox = current.outbox
          .where(
            (PendingMutation item) =>
                item.isLabel ||
                item.mutation.identityFor(accountUserId) != local.identity,
          )
          .toList();
      final pendingProtection = current.outbox
          .where(
            (m) =>
                !m.isLabel &&
                m.mutation.identityFor(accountUserId) == local.identity &&
                m.protectionChange != null,
          )
          .lastOrNull
          ?.protectionChange;
      if (pendingProtection != null &&
          choice == SyncConflictChoice.useLocal &&
          (conflict.remote?.isDeleted == true ||
              local.isDeleted ||
              (conflict.remote?.protection.revision ?? 0) >=
                  pendingProtection.after.revision)) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.staleRevision);
      }
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
          ownerId: local.ownerId,
          noteId: local.id,
          protection: local.protection,
          operation: operation,
        );
        // Copying a protected deleted note into another identity is export.
        if (choice == SyncConflictChoice.useLocal &&
            (remote == null || remote.isDeleted)) {
          guard.requireAccess(
            ownerId: local.ownerId,
            noteId: local.id,
            protection: local.protection,
            operation: NoteOperation.export,
          );
        }
      }

      if (choice == SyncConflictChoice.useRemote) {
        if (remote != null) {
          notes.add(_fromRemote(remote, accountUserId, previous: local));
        }
      } else if (remote == null) {
        if (!local.isDeleted) {
          notes.add(_pendingNote(local, serverRevision: 0));
          outbox.add(
            _mutation(
              id: local.id,
              operation: SyncMutationOperation.create,
              baseRevision: 0,
              local: local,
              accountUserId: accountUserId,
              timestamp: timestamp,
              includeLabels: conflict.pending.payload?.includesLabels == true,
              protectionChange: pendingProtection == null
                  ? null
                  : ProtectionSyncChange(
                      before:
                          conflict.remote?.protection ??
                          const NoteProtection.unprotected(),
                      after: pendingProtection.after,
                      verifier: pendingProtection.verifier,
                    ),
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
              accountUserId: accountUserId,
              timestamp: timestamp,
              includeLabels: conflict.pending.payload?.includesLabels == true,
              protectionChange: pendingProtection == null
                  ? null
                  : ProtectionSyncChange(
                      before:
                          conflict.remote?.protection ??
                          const NoteProtection.unprotected(),
                      after: pendingProtection.after,
                      verifier: pendingProtection.verifier,
                    ),
            ),
          );
        }
      } else if (remote.isDeleted) {
        if (local.attachments.isNotEmpty) {
          throw StateError(
            'Copying attachments to a new note requires authorized object rebinding.',
          );
        }
        final LocalNoteState replacement = LocalNoteState(
          id: generateNoteId(),
          ownerId: accountUserId,
          title: local.title,
          content: local.content,
          createdAt: local.createdAt,
          updatedAt: timestamp,
          pinnedAt: local.pinnedAt,
          attachments: local.attachments,
          labelIds: local.labelIds,
          labelProjections: local.labelProjections,
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
            accountUserId: accountUserId,
            timestamp: timestamp,
            includeLabels: conflict.pending.payload?.includesLabels == true,
          ),
        );
      } else {
        notes.add(_pendingNote(local, serverRevision: remote.revision));
        outbox.add(
          _mutation(
            id: local.id,
            operation: SyncMutationOperation.update,
            baseRevision: remote.revision,
            protectionChange: pendingProtection == null
                ? null
                : ProtectionSyncChange(
                    before: remote.protection,
                    after: pendingProtection.after,
                    verifier: pendingProtection.verifier,
                  ),
            local: local,
            accountUserId: accountUserId,
            timestamp: timestamp,
            includeLabels: conflict.pending.payload?.includesLabels == true,
          ),
        );
      }

      final List<SyncConflict> conflicts = current.conflicts.toList()
        ..removeAt(conflictIndex);
      return LocalSyncState(
        accountUserId: current.accountUserId,
        labels: current.labels,
        syncWireVersion: current.syncWireVersion,
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
    required String accountUserId,
    required DateTime timestamp,
    ProtectionSyncChange? protectionChange,
    bool includeLabels = false,
  }) => PendingMutation(
    mutationId: generateMutationId(),
    noteId: id,
    ownerId: local.ownerId == accountUserId ? null : local.ownerId,
    accessRevision: local.share?.accessRevision,
    operation: operation,
    protectionChange: protectionChange,
    baseRevision: baseRevision,
    payload: operation == SyncMutationOperation.delete
        ? null
        : SyncNotePayload(
            title: local.title,
            content: local.content,
            labelMembership: LabelMembership(local.labelIds),
            includesLabels:
                local.share == null &&
                (local.labelIds.isNotEmpty || includeLabels),
            pinnedAt: local.pinnedAt,
            includesPinnedAt: local.share == null,
            attachmentManifest: AttachmentManifest(local.attachments),
            includesAttachments:
                local.share == null && local.attachments.isNotEmpty,
          ),
    createdAt: timestamp,
  );
}

LocalNoteState? _findNote(LocalSyncState state, NoteIdentity identity) {
  for (final LocalNoteState note in state.notes) {
    if (note.identity == identity) return note;
  }
  return null;
}

LocalNoteState _pendingNote(
  LocalNoteState note, {
  required int serverRevision,
}) => LocalNoteState(
  id: note.id,
  ownerId: note.ownerId,
  share: note.share,
  title: note.title,
  content: note.content,
  createdAt: note.createdAt,
  updatedAt: note.updatedAt,
  pinnedAt: note.pinnedAt,
  attachments: note.attachments,
  labelIds: note.labelIds,
  labelProjections: note.labelProjections,
  serverRevision: serverRevision,
  deletedAt: note.deletedAt,
  status: NoteSyncStatus.pending,
  protection: note.protection,
  contentAvailable: note.contentAvailable,
);

LocalNoteState _fromRemote(
  SyncNoteSnapshot note,
  String accountUserId, {
  LocalNoteState? previous,
}) => LocalNoteState(
  id: note.id,
  ownerId: note.ownerId ?? accountUserId,
  share: note.share,
  title: note.title,
  content: note.content,
  createdAt: note.createdAt,
  updatedAt: note.serverUpdatedAt,
  pinnedAt: note.pinnedAt,
  attachments: !note.contentAvailable || note.isDeleted
      ? const []
      : note.includesAttachments
      ? note.attachments
      : previous?.attachments ?? const [],
  labelIds: !note.contentAvailable || note.isDeleted
      ? const []
      : note.includesLabels
      ? note.labelIds
      : previous?.labelIds ?? const [],
  labelProjections: !note.contentAvailable || note.isDeleted
      ? const []
      : note.includesLabels
      ? note.labelProjections
      : previous?.labelProjections ?? const [],
  serverRevision: note.revision,
  deletedAt: note.deletedAt,
  status: NoteSyncStatus.synced,
  protection: note.protection,
  contentAvailable: note.contentAvailable,
);
