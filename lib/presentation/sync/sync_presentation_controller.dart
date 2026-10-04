import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../application/sync/local_note_state.dart';
import '../../application/sync/local_sync_state.dart';
import '../../application/sync/local_sync_store.dart';
import '../../application/sync/sync_metadata_projection.dart';
import '../../application/sync/note_sync_status.dart';
import '../../application/sync/sync_conflict.dart';
import '../../application/sync/sync_conflict_resolver.dart';
import '../../application/sync/sync_coordinator.dart';
import '../../application/sync/sync_failure.dart';
import '../../application/sync/sync_status.dart';

/// Account-scoped Presentation state for the existing sync Application ports.
final class SyncPresentationController extends ChangeNotifier {
  SyncPresentationController({
    required this.accountUserId,
    required this.localStore,
    required this.coordinator,
    required this.conflictResolver,
    Stream<void> securityEvents = const Stream<void>.empty(),
    this.isCurrentSession,
  }) : _status = coordinator.status {
    if (accountUserId.trim().isEmpty) {
      throw ArgumentError.value(accountUserId, 'accountUserId');
    }
    _statusSubscription = coordinator.statusChanges.listen((
      SyncStatusSnapshot value,
    ) {
      if (!_live) return;
      _status = value;
      notifyListeners();
      unawaited(refresh());
    });
    _securitySubscription = securityEvents.listen((_) {
      if (_disposed) return;
      _readSequence++;
      _localState = null;
      _loadError = null;
      notifyListeners();
      if (_live) unawaited(refresh());
    });
    unawaited(refresh());
  }

  final String accountUserId;
  final ILocalSyncStore localStore;
  final ISyncCoordinator coordinator;
  final SyncConflictResolver conflictResolver;
  final bool Function()? isCurrentSession;
  bool get _live => !_disposed && (isCurrentSession?.call() ?? true);
  late final StreamSubscription<void> _securitySubscription;

  late final StreamSubscription<SyncStatusSnapshot> _statusSubscription;
  SyncStatusSnapshot _status;
  LocalSyncState? _localState;
  Object? _loadError;
  int _readSequence = 0;
  bool _disposed = false;

  SyncStatusSnapshot get status => _status;
  LocalSyncState? get localState => _localState;
  Object? get loadError => _loadError;
  bool get isLoading => _localState == null && _loadError == null;
  int get pendingCount => _localState?.outbox.length ?? 0;
  int get conflictCount => _localState?.conflicts.length ?? 0;
  int get blockedInvalidMutationCount =>
      _localState?.outbox
          .where(
            (entry) =>
                entry.blocked &&
                entry.lastError == SyncErrorCode.invalidMutation,
          )
          .length ??
      0;

  SyncConflict? conflictFor(String noteId) {
    for (final SyncConflict conflict
        in _localState?.conflicts ?? const <SyncConflict>[]) {
      if (conflict.identity.referenceFor(accountUserId) == noteId) {
        return conflict;
      }
    }
    return null;
  }

  NoteSyncStatus? noteStatusFor(String noteId) {
    final LocalSyncState? state = _localState;
    if (state == null) return null;
    if (state.conflicts.any(
      (SyncConflict item) =>
          item.identity.referenceFor(accountUserId) == noteId,
    )) {
      return NoteSyncStatus.conflict;
    }
    LocalNoteState? note;
    for (final LocalNoteState item in state.notes) {
      if (item.referenceFor(accountUserId) == noteId) {
        note = item;
        break;
      }
    }
    if (note == null) return null;
    if (note.status == NoteSyncStatus.failed ||
        state.outbox.any(
          (entry) =>
              !entry.isLabel &&
              entry.mutation
                      .identityFor(accountUserId)
                      .referenceFor(accountUserId) ==
                  noteId &&
              entry.lastError != null,
        )) {
      return NoteSyncStatus.failed;
    }
    return note.status;
  }

  /// Rereads this account's state. A read error is exposed separately from
  /// network status so storage failures are not mislabeled as offline.
  Future<void> refresh() async {
    if (!_live) return;
    final int sequence = ++_readSequence;
    try {
      final LocalSyncState state = await localStore.read();
      _validateAccount(state);
      if (!_live || sequence != _readSequence) return;
      _localState = SyncMetadataProjection.state(state);
      _loadError = null;
    } on Object catch (error) {
      if (!_live || sequence != _readSequence) return;
      _loadError = error;
    }
    if (_live) notifyListeners();
  }

  /// Runs a best-effort foreground sync; the coordinator retains its status.
  Future<void> syncNow() async {
    if (!_live) return;
    try {
      await coordinator.syncNow();
    } on Object {
      // The coordinator publishes the mapped failure to [statusChanges].
    } finally {
      await refresh();
    }
  }

  /// Resolves only the conflict version currently stored for this account.
  /// Returns false when it disappeared or changed while the chooser was open.
  Future<bool> resolveConflict({
    required SyncConflict displayedConflict,
    required SyncConflictChoice choice,
  }) async {
    if (!_live) return false;
    final int sequence = ++_readSequence;
    final LocalSyncState latest;
    try {
      latest = await localStore.read();
      _validateAccount(latest);
    } on Object catch (error) {
      if (_live) {
        _loadError = error;
        notifyListeners();
      }
      return false;
    }
    if (!_live) return false;
    if (!_live || sequence != _readSequence) return false;
    _localState = SyncMetadataProjection.state(latest);
    _loadError = null;
    notifyListeners();

    SyncConflict? current;
    for (final SyncConflict item in latest.conflicts) {
      if (item.identity == displayedConflict.identity) {
        current = item;
        break;
      }
    }
    if (choice == SyncConflictChoice.later) return current != null;
    if (current == null ||
        SyncMetadataProjection.conflict(current) !=
            SyncMetadataProjection.conflict(displayedConflict)) {
      return false;
    }

    try {
      await conflictResolver.resolve(
        accountUserId: accountUserId,
        conflict: current,
        choice: choice,
      );
    } on Object {
      await refresh();
      return false;
    }
    await refresh();
    if (choice == SyncConflictChoice.useLocal) unawaited(syncNow());
    return _live;
  }

  void _validateAccount(LocalSyncState state) {
    if (state.accountUserId != accountUserId) {
      throw const SyncFailure(code: SyncErrorCode.forbidden);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _readSequence++;
    _localState = null;
    unawaited(_securitySubscription.cancel());
    unawaited(_statusSubscription.cancel());
    super.dispose();
  }
}
