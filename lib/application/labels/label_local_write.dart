import '../../domain/labels/label.dart';
import '../sync/local_sync_state.dart';
import '../sync/pending_mutation.dart';
import '../sync/sync_mutation.dart';
import '../sync/sync_failure.dart';
import '../sync/note_sync_status.dart';
import 'local_label_state.dart';

/// Pure transition executed INSIDE the existing actor store's atomic update.
({LocalSyncState state, LocalLabelState label, bool changed}) writeLocalLabel(
  LocalSyncState state, {
  required String actor,
  required String resource,
  required bool creating,
  required bool deleting,
  required String? name,
  required DateTime timestamp,
  required String mutationId,
}) {
  if (state.accountUserId != actor) {
    throw const SyncFailure(code: SyncErrorCode.forbidden);
  }
  final old = state.labels.where((l) => l.id == resource).firstOrNull;
  if (!creating && old == null) throw StateError('Label no longer exists.');
  if (old?.status == NoteSyncStatus.conflict) {
    throw StateError('Resolve the label conflict first.');
  }
  final domain =
      old?.toDomain() ??
      Label.create(id: resource, ownerId: actor, name: name!, now: timestamp);
  if (old != null) {
    deleting ? domain.delete(timestamp) : domain.rename(name!, timestamp);
    if (old.name == domain.name && old.deletedAt == domain.deletedAt) {
      return (state: state, label: old, changed: false);
    }
  }
  var label = LocalLabelState(
    id: resource,
    ownerId: actor,
    name: domain.name,
    createdAt: domain.createdAt,
    updatedAt: domain.updatedAt,
    deletedAt: domain.deletedAt,
    serverRevision: old?.serverRevision ?? 0,
    status: NoteSyncStatus.pending,
  );
  final requests = state.outbox
      .where((m) => m.isLabel && m.noteId == resource)
      .toList();
  final canceledCreate =
      deleting &&
      old?.serverRevision == 0 &&
      requests.isNotEmpty &&
      requests.every((m) => m.retryCount == 0 && !m.blocked);
  final outbox = canceledCreate
      ? state.outbox.where((m) => !m.isLabel || m.noteId != resource).toList()
      : queueLabelWrite(state, label, old, timestamp, mutationId);
  if (canceledCreate) label = label.withStatus(NoteSyncStatus.synced);
  return (
    state: LocalSyncState(
      accountUserId: actor,
      notes: state.notes,
      conflicts: state.conflicts,
      cursor: state.cursor,
      userPreferences: state.userPreferences,
      syncWireVersion: state.syncWireVersion,
      outbox: outbox,
      labels: [...state.labels.where((l) => l.id != resource), label],
    ),
    label: label,
    changed: true,
  );
}

List<PendingMutation> queueLabelWrite(
  LocalSyncState state,
  LocalLabelState label,
  LocalLabelState? old,
  DateTime timestamp,
  String mutationId,
) {
  final last = state.outbox
      .where((m) => m.isLabel && m.noteId == label.id)
      .lastOrNull;
  final unsent = last != null && last.retryCount == 0 && !last.blocked;
  final repairing =
      last?.blocked == true && last?.lastError == SyncErrorCode.invalidMutation;
  final outbox = List<PendingMutation>.of(state.outbox);
  if (repairing) outbox.removeWhere((m) => m.isLabel && m.noteId == label.id);
  final next = PendingMutation(
    mutationId: unsent ? last.mutationId : mutationId,
    noteId: label.id,
    entityType: SyncEntityType.label,
    labelName: label.isDeleted ? null : label.name,
    operation: label.isDeleted
        ? SyncMutationOperation.delete
        : unsent
        ? last.operation
        : old == null || old.serverRevision == 0 && (last == null || repairing)
        ? SyncMutationOperation.create
        : SyncMutationOperation.update,
    baseRevision: unsent
        ? last.baseRevision
        : last != null && !repairing
        ? last.baseRevision + 1
        : old?.serverRevision ?? 0,
    createdAt: unsent ? last.createdAt : timestamp,
  );
  if (unsent) {
    outbox[outbox.indexOf(last)] = next;
  } else {
    outbox.add(next);
  }
  return outbox;
}
