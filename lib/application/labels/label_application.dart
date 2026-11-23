import 'dart:async';

import '../../domain/notes/note_repository.dart';
import '../notes/note_dto.dart';
import '../sync/local_sync_store.dart';
import '../sync/local_sync_state.dart';
import '../sync/note_sync_status.dart';
import '../sync/pending_mutation.dart';
import '../sync/sync_mutation.dart';
import '../sync/sync_failure.dart';
import 'local_label_state.dart';
import 'label_local_write.dart';

/// Local-first catalog use cases over the SAME actor store used by Note/sync.
final class LabelApplication {
  LabelApplication({
    required this.currentActor,
    required this.generation,
    required this.storeFor,
    required this.notes,
    required this.generateId,
    required this.now,
    required this.requestSync,
  });
  final String Function() currentActor;
  final int Function() generation;
  final ILocalSyncStore Function(String actor) storeFor;
  final INoteRepository notes;
  final String Function() generateId;
  final DateTime Function() now;
  final void Function(String actor) requestSync;
  final _events = StreamController<void>.broadcast(sync: true);
  Stream<void> get changes => _events.stream;
  void notifyChanged() {
    if (!_events.isClosed) _events.add(null);
  }

  ({String actor, int epoch}) _capture() {
    final actor = currentActor();
    if (actor.trim().isEmpty) {
      throw const SyncFailure(code: SyncErrorCode.unauthorized);
    }
    return (actor: actor, epoch: generation());
  }

  void _fence(({String actor, int epoch}) c) {
    if (currentActor() != c.actor || generation() != c.epoch) {
      throw const SyncFailure(code: SyncErrorCode.unauthorized);
    }
  }

  Future<List<LocalLabelState>> list() async {
    final c = _capture();
    final state = await storeFor(c.actor).read();
    _fence(c);
    if (state.accountUserId != c.actor) {
      throw const SyncFailure(code: SyncErrorCode.forbidden);
    }
    return state.labels;
  }

  Future<LocalLabelState> create(String name) => _write(null, name, false);
  Future<LocalLabelState> rename(String id, String name) =>
      _write(id, name, false);
  Future<LocalLabelState> delete(String id) => _write(id, null, true);

  Future<LocalLabelState> _write(
    String? id,
    String? name,
    bool deleting,
  ) async {
    final c = _capture(), timestamp = now().toUtc();
    final resource = id ?? generateId();
    final mutationId = generateId();
    LocalLabelState? result;
    var changed = false;
    await storeFor(c.actor).update((state) {
      _fence(c);
      final transition = writeLocalLabel(
        state,
        actor: c.actor,
        resource: resource,
        creating: id == null,
        deleting: deleting,
        name: name,
        timestamp: timestamp,
        mutationId: mutationId,
      );
      result = transition.label;
      changed = transition.changed;
      return transition.state;
    });
    _fence(c);
    if (changed) {
      _events.add(null);
      requestSync(c.actor);
    }
    return result!;
  }

  Future<NoteDto> setAttached(
    NoteDto note,
    String labelId,
    bool attached,
  ) async {
    final c = _capture();
    if (note.ownerId != c.actor) {
      throw const SyncFailure(code: SyncErrorCode.forbidden);
    }
    final catalog = await list();
    _fence(c);
    final label = catalog.where((l) => l.id == labelId).firstOrNull;
    if (attached && (label == null || label.isDeleted)) {
      throw StateError('Label no longer active.');
    }
    final result = await notes.updateById(
      noteId: note.id,
      ownerId: note.ownerId,
      expectedAccountUserId: c.actor,
      canCommit: () => currentActor() == c.actor && generation() == c.epoch,
      change: (fresh) {
        attached
            ? fresh.attachLabel(label!.toDomain(), now())
            : fresh.detachLabel(labelId, now());
        return fresh;
      },
    );
    _fence(c);
    _events.add(null);
    requestSync(c.actor);
    return NoteDto.fromDomain(result);
  }

  /// Explicit conflict choice. Kept local uses a fresh mutation ID.
  Future<void> resolve(String id, {required bool useCloud}) async {
    final c = _capture(), mutationId = generateId(), timestamp = now().toUtc();
    await storeFor(c.actor).update((state) {
      _fence(c);
      final old = state.labels.where((l) => l.id == id).firstOrNull;
      if (old == null || old.status != NoteSyncStatus.conflict) return state;
      final remote = old.conflictRemote;
      final outbox = state.outbox
          .where((m) => !m.isLabel || m.noteId != id)
          .toList();
      final labels = state.labels.where((l) => l.id != id).toList();
      if (useCloud) {
        if (remote != null) labels.add(remote);
      } else {
        if (remote?.isDeleted == true && !old.isDeleted) {
          throw StateError(
            'Deleted label cannot be restored. Create a new label.',
          );
        }
        labels.add(
          old.withStatus(
            NoteSyncStatus.pending,
            revision: remote?.serverRevision ?? 0,
          ),
        );
        outbox.add(
          PendingMutation(
            mutationId: mutationId,
            noteId: id,
            entityType: SyncEntityType.label,
            labelName: old.isDeleted ? null : old.name,
            operation: old.isDeleted
                ? SyncMutationOperation.delete
                : remote == null
                ? SyncMutationOperation.create
                : SyncMutationOperation.update,
            baseRevision: remote?.serverRevision ?? 0,
            createdAt: timestamp,
          ),
        );
      }
      return _copy(state, labels: labels, outbox: outbox);
    });
    _fence(c);
    _events.add(null);
    requestSync(c.actor);
  }

  LocalSyncState _copy(
    LocalSyncState s, {
    required Iterable<LocalLabelState> labels,
    required Iterable<PendingMutation> outbox,
  }) => LocalSyncState(
    accountUserId: s.accountUserId,
    notes: s.notes,
    conflicts: s.conflicts,
    cursor: s.cursor,
    userPreferences: s.userPreferences,
    labels: labels,
    syncWireVersion: s.syncWireVersion,
    outbox: outbox,
  );
  Future<void> dispose() => _events.close();
}
