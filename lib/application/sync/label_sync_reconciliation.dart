import '../labels/local_label_state.dart';
import 'local_sync_state.dart';
import 'note_sync_status.dart';
import 'pending_mutation.dart';
import 'sync_failure.dart';
import 'sync_result.dart';
import 'sync_state_reconciliation.dart';

/// Label outcomes share the Note coordinator, cursor and atomic store.
final class LabelSyncReconciliation {
  const LabelSyncReconciliation(this.state);
  final SyncStateReconciliation state;
  Future<bool> apply(
    PendingMutation requested,
    SyncMutationResult result,
  ) async {
    final remote = result.isApplied ? result.label : result.labelRemote;
    if (result.isApplied &&
        remote?.serverRevision != requested.baseRevision + 1) {
      throw const SyncFailure(code: SyncErrorCode.unexpected);
    }
    if (remote != null &&
            (remote.ownerId != state.accountUserId ||
                remote.id != requested.noteId) ||
        result.isApplied && remote == null ||
        result.note != null ||
        result.conflictRemote != null) {
      throw const SyncFailure(code: SyncErrorCode.unexpected);
    }
    var applied = false;
    await state.update((current) {
      final entry = current.outbox
          .where((m) => m.mutationId == requested.mutationId && m.isLabel)
          .firstOrNull;
      if (entry == null) return current;
      final old = current.labels
          .where((l) => l.id == requested.noteId)
          .firstOrNull;
      if (old == null) throw const SyncFailure(code: SyncErrorCode.unexpected);
      final outbox = List<PendingMutation>.of(current.outbox);
      final labels = List<LocalLabelState>.of(current.labels);
      final index = labels.indexOf(old);
      if (result.isConflict) {
        outbox[outbox.indexOf(entry)] = state.copyEntry(entry, blocked: true);
        labels[index] = old.withStatus(NoteSyncStatus.conflict, remote: remote);
      } else {
        outbox.remove(entry);
        final later = outbox.any((m) => m.isLabel && m.noteId == old.id);
        labels[index] = later
            ? old.withStatus(
                NoteSyncStatus.pending,
                revision: remote!.serverRevision,
              )
            : remote!;
      }
      applied = true;
      return state.copyState(current, labels: labels, outbox: outbox);
    });
    return applied;
  }

  List<LocalLabelState> mergePage(
    LocalSyncState current,
    Iterable<LocalLabelState> remote,
  ) {
    final labels = List<LocalLabelState>.of(current.labels);
    for (final incoming in remote) {
      if (incoming.ownerId != state.accountUserId) {
        throw const SyncFailure(code: SyncErrorCode.forbidden);
      }
      final index = labels.indexWhere((l) => l.id == incoming.id);
      final old = index < 0 ? null : labels[index];
      if (old?.status == NoteSyncStatus.conflict) {
        if (incoming.serverRevision >
            (old!.conflictRemote?.serverRevision ?? 0)) {
          labels[index] = old.withStatus(
            NoteSyncStatus.conflict,
            remote: incoming,
          );
        }
        continue;
      }
      if (current.outbox.any((m) => m.isLabel && m.noteId == incoming.id) ||
          old != null && incoming.serverRevision <= old.serverRevision) {
        continue;
      }
      if (index < 0) {
        labels.add(incoming);
      } else {
        labels[index] = incoming;
      }
    }
    return labels;
  }
}
