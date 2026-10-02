import 'dart:async';

import 'local_sync_state.dart';
import 'local_sync_store.dart';
import 'pending_mutation.dart';
import 'remote_note_data_source.dart';
import 'sync_conflict.dart';
import 'sync_coordinator.dart';
import 'sync_cursor.dart';
import 'sync_failure.dart';
import 'sync_report.dart';
import 'sync_result.dart';
import 'sync_snapshot.dart';
import 'sync_state_reconciliation.dart';
import 'sync_status.dart';

/// Runs account-bound synchronization against the local store and remote API.
final class SyncCoordinatorService implements ISyncCoordinator {
  SyncCoordinatorService({
    required this.accountUserId,
    required ILocalSyncStore localStore,
    required this.remote,
    this.observeSnapshot,
    this.hydrateSnapshot,
    this.requireSession,
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
  }) : _reconciliation = SyncStateReconciliation(
         accountUserId: accountUserId,
         localStore: localStore,
         clock: clock ?? DateTime.now,
       ),
       _delay = delay ?? Future<void>.delayed;

  final String accountUserId;
  final IRemoteNoteDataSource remote;
  final Future<void> Function(SyncNoteSnapshot)? observeSnapshot;
  final Future<void> Function(SyncNoteSnapshot)? hydrateSnapshot;
  final void Function()? requireSession;
  final SyncStateReconciliation _reconciliation;
  final Future<void> Function(Duration) _delay;
  final StreamController<SyncStatusSnapshot> _statuses =
      StreamController<SyncStatusSnapshot>.broadcast();

  SyncStatusSnapshot _status = const SyncStatusSnapshot.idle();
  Future<SyncReport>? _inFlight;
  bool _rerun = false;
  bool _disposed = false;

  @override
  SyncStatusSnapshot get status => _status;

  @override
  Stream<SyncStatusSnapshot> get statusChanges => _statuses.stream;

  /// Closes the status stream. Safe to call more than once.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _statuses.close();
  }

  @override
  Future<SyncReport> syncNow() {
    if (_disposed) {
      return Future<SyncReport>.error(
        const SyncFailure(code: SyncErrorCode.unexpected),
      );
    }
    final Future<SyncReport>? current = _inFlight;
    if (current != null) {
      _rerun = true;
      return current;
    }
    final Future<SyncReport> run = _runCoalesced().whenComplete(
      () => _inFlight = null,
    );
    _inFlight = run;
    return run;
  }

  Future<SyncReport> _runCoalesced() async {
    _publish(const SyncStatusSnapshot.syncing());
    try {
      SyncReport report = SyncReport();
      do {
        _rerun = false;
        report = await _syncPass();
      } while (_rerun);
      _publish(const SyncStatusSnapshot.idle());
      return report;
    } on SyncFailure catch (failure) {
      _publish(
        failure.code == SyncErrorCode.networkUnavailable
            ? const SyncStatusSnapshot.offline()
            : SyncStatusSnapshot.failed(failure),
      );
      rethrow;
    } catch (_) {
      const SyncFailure failure = SyncFailure(code: SyncErrorCode.unexpected);
      _publish(SyncStatusSnapshot.failed(failure));
      throw failure;
    }
  }

  Future<SyncReport> _syncPass() async {
    requireSession?.call();
    LocalSyncState state = await _reconciliation.read();
    final SyncCursor? initialCursor = state.cursor;
    int applied = 0;
    int pulled = 0;
    int conflicts = 0;
    final Set<String> stoppedNotes = <String>{
      ...state.outbox
          .where((PendingMutation item) => item.blocked)
          .map((PendingMutation item) => item.keyFor(accountUserId)),
      ...state.conflicts.map((SyncConflict item) => item.identity.key),
    };
    final Set<String> attempted = <String>{};

    pushQueue:
    while (true) {
      state = await _reconciliation.read();
      stoppedNotes.addAll(
        state.outbox
            .where((PendingMutation item) => item.blocked)
            .map((PendingMutation item) => item.keyFor(accountUserId)),
      );
      stoppedNotes.addAll(
        state.conflicts.map((SyncConflict item) => item.identity.key),
      );
      final PendingMutation? entry = state.outbox
          .cast<PendingMutation?>()
          .firstWhere(
            (PendingMutation? item) =>
                item != null &&
                !item.blocked &&
                !stoppedNotes.contains(item.keyFor(accountUserId)) &&
                !attempted.contains(item.mutationId),
            orElse: () => null,
          );
      if (entry == null) break;
      attempted.add(entry.mutationId);

      SyncMutationResult result;
      var tries = 0;
      while (true) {
        state = await _reconciliation.update((current) {
          final int index = current.outbox.indexWhere(
            (PendingMutation item) =>
                item.mutationId == entry.mutationId && !item.blocked,
          );
          if (index < 0 ||
              current.conflicts.any(
                (SyncConflict item) =>
                    item.identity == entry.mutation.identityFor(accountUserId),
              )) {
            return current;
          }
          final List<PendingMutation> outbox = List<PendingMutation>.of(
            current.outbox,
          );
          outbox[index] = _reconciliation.copyEntry(
            outbox[index],
            retryCount: outbox[index].retryCount + 1,
          );
          return _reconciliation.copyState(current, outbox: outbox);
        });
        final int sendingIndex = state.outbox.indexWhere(
          (PendingMutation item) => item.mutationId == entry.mutationId,
        );
        if (sendingIndex < 0 ||
            state.outbox[sendingIndex].blocked ||
            state.conflicts.any(
              (SyncConflict item) =>
                  item.identity == entry.mutation.identityFor(accountUserId),
            )) {
          continue pushQueue;
        }
        final PendingMutation prepared = state.outbox[sendingIndex];
        try {
          result = await remote.push(prepared.toMutation());
          requireSession?.call();
          break;
        } on SyncFailure catch (failure) {
          tries++;
          if (!failure.retryable || tries >= 2) {
            await _reconciliation.recordPushFailure(entry.mutationId, failure);
            if (failure.code == SyncErrorCode.forbidden) {
              stoppedNotes.add(entry.keyFor(accountUserId));
              continue pushQueue;
            }
            rethrow;
          }
          await _delay(const Duration(milliseconds: 100));
        }
      }

      if (result.mutationId != entry.mutationId) {
        throw const SyncFailure(code: SyncErrorCode.unexpected);
      }
      if (result.isConflict) {
        if (result.conflictRemote case final snapshot?) {
          await observeSnapshot?.call(snapshot);
        }
        if (await _reconciliation.recordConflict(entry, result)) {
          stoppedNotes.add(entry.keyFor(accountUserId));
          conflicts++;
        }
        continue;
      }
      final SyncNoteSnapshot? snapshot = result.note;
      if (snapshot == null ||
          snapshot.identityFor(accountUserId) !=
              entry.mutation.identityFor(accountUserId)) {
        throw const SyncFailure(code: SyncErrorCode.unexpected);
      }
      await observeSnapshot?.call(snapshot);
      requireSession?.call();
      if (await _reconciliation.acknowledge(entry, snapshot)) applied++;
    }

    while (true) {
      state = await _reconciliation.read();
      final String? requestCursor = state.cursor?.value;
      final SyncChangesPage page = await remote.pull(cursor: requestCursor);
      requireSession?.call();
      if (page.hasMore && page.nextCursor == requestCursor) {
        throw const SyncFailure(code: SyncErrorCode.unexpected);
      }
      for (final snapshot in page.snapshots) {
        await observeSnapshot?.call(snapshot);
        requireSession?.call();
      }
      final SyncPageApply appliedPage = await _reconciliation.applyPage(
        page,
        expectedCursor: requestCursor,
      );
      if (!appliedPage.cursorMatched) continue;
      for (final snapshot in page.snapshots) {
        await hydrateSnapshot?.call(snapshot);
        requireSession?.call();
      }
      pulled += appliedPage.pulled;
      if (!page.hasMore) break;
    }

    state = await _reconciliation.read();
    if (state.outbox.any(
      (m) =>
          !m.blocked &&
          !stoppedNotes.contains(m.keyFor(accountUserId)) &&
          !attempted.contains(m.mutationId) &&
          !state.conflicts.any(
            (c) => c.identity == m.mutation.identityFor(accountUserId),
          ),
    )) {
      _rerun = true;
    }
    return SyncReport(
      applied: applied,
      pulled: pulled,
      conflicts: conflicts,
      cursor: state.cursor == initialCursor ? null : state.cursor,
    );
  }

  void _publish(SyncStatusSnapshot status) {
    _status = status;
    if (!_disposed) _statuses.add(status);
  }
}
