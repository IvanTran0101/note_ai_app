import 'dart:async';

import '../../domain/notes/note_protection.dart';
import '../auth/current_user.dart';
import '../auth/current_user_session.dart';
import '../sync/local_note_state.dart';
import '../sync/local_sync_state.dart';
import '../sync/local_sync_store.dart';
import '../sync/sync_snapshot.dart';
import '../sync/pending_mutation.dart';
import '../sync/sync_failure.dart';
import 'local_note_vault.dart';
import 'note_access.dart';
import 'note_security_gateway.dart';

part 'note_security_actions.dart';

typedef _LocalAccess = ({
  NoteProtection protection,
  Set<NoteOperation> operations,
  DateTime expiresAt,
  int session,
  bool online,
});

/// Owns unlock/session/expiry policy. No Flutter, storage SDK or crypto types.
final class NoteSecurityService implements INoteAccessGuard {
  NoteSecurityService({
    required this.accountId,
    required this.currentUser,
    required this.session,
    required this.store,
    required this.vault,
    required this.gateway,
    this.syncNow,
    this.cancelSummaries,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final String accountId;
  final ICurrentUser currentUser;
  final SessionGenerationSource session;
  final ILocalSyncStore store;
  final ILocalNoteVault vault;
  final INoteSecurityGateway gateway;
  final Future<void> Function()? syncNow;
  final void Function()? cancelSummaries;
  final DateTime Function() _now;
  final _knownProtection = <String, NoteProtection>{};
  final _access = <String, _LocalAccess>{};
  final _timers = <String, Timer>{};
  final _changes = StreamController<void>.broadcast(sync: true);
  int _generation = 0;
  bool _disposed = false;
  Stream<void> get changes => _changes.stream;
  @override
  int get accessGeneration => _generation;

  int _capture() {
    if (_disposed || currentUser.userId != accountId) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
    return session.sessionGeneration;
  }

  void _live(int captured, int generation) {
    if (_capture() != captured || generation != _generation) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
  }

  Future<LocalNoteState> _note(String id) async {
    final note = (await store.read()).notes
        .where((n) => n.id == id && !n.isDeleted)
        .firstOrNull;
    if (note == null || note.ownerId != accountId) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
    }
    return note;
  }

  @override
  bool allows({
    required String ownerId,
    required String noteId,
    required NoteProtection protection,
    required NoteOperation operation,
  }) {
    if (_disposed || currentUser.userId != accountId || ownerId != accountId) {
      return false;
    }
    if (_knownProtection[noteId] != null &&
        _knownProtection[noteId] != protection) {
      return false;
    }
    if (!protection.enabled) return true;
    final active = _access[noteId];
    return active != null &&
        active.protection == protection &&
        active.session == session.sessionGeneration &&
        active.expiresAt.isAfter(_now()) &&
        active.operations.contains(operation) &&
        vault.isLocallyUnlocked(noteId, protection) &&
        !(operation == NoteOperation.edit &&
            vault.hasRetainedCiphertext(noteId));
  }

  @override
  void requireAccess({
    required String ownerId,
    required String noteId,
    required NoteProtection protection,
    required NoteOperation operation,
  }) {
    if (!allows(
      ownerId: ownerId,
      noteId: noteId,
      protection: protection,
      operation: operation,
    )) {
      if (_access[noteId]?.expiresAt.isAfter(_now()) == false) lock(noteId);
      throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
    }
  }

  void requireRemote(String id, NoteProtection p, NoteOperation operation) {
    _capture();
    if (p.enabled && !gateway.hasAuthority(id, p, operation)) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
    }
  }

  Future<NoteProtection> refreshProtection(String id) async {
    final captured = _capture(), generation = _generation;
    final p = await gateway.metadata(id);
    _live(captured, generation);
    final previous = (await _note(id)).protection;
    _live(captured, generation);
    _knownProtection[id] = p;
    if (previous != p) lock(id);
    final observedGeneration = _generation;
    await vault.observeProtection(id, p);
    _live(captured, observedGeneration);
    return p;
  }

  Future<void> _hydrateAuthorized(String id, NoteProtection p) async {
    requireRemote(id, p, NoteOperation.read);
    final content = await gateway.content(id);
    requireRemote(id, p, NoteOperation.read);
    if (content.protection != p) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.staleRevision);
    }
    await vault.hydrate(content);
  }

  Future<void> observeSnapshot(SyncNoteSnapshot snapshot) async {
    final captured = _capture();
    final note = (await store.read()).notes
        .where((n) => n.id == snapshot.id)
        .firstOrNull;
    if (note == null) return;
    if (_capture() != captured) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
    _knownProtection[snapshot.id] = snapshot.protection;
    if (note.protection != snapshot.protection) lock(snapshot.id);
    await vault.observeProtection(snapshot.id, snapshot.protection);
  }

  /// Pull remains metadata-only; hydrate only a currently authorized note.
  Future<void> hydrateSnapshot(SyncNoteSnapshot snapshot) async {
    final captured = _capture(), generation = _generation;
    if (!snapshot.protection.enabled ||
        snapshot.isDeleted ||
        !gateway.hasAuthority(
          snapshot.id,
          snapshot.protection,
          NoteOperation.read,
        )) {
      return;
    }
    try {
      await _hydrateAuthorized(snapshot.id, snapshot.protection);
      _live(captured, generation);
    } on NoteSecurityFailure catch (failure) {
      lock(snapshot.id);
      if (failure.code == NoteSecurityFailureCode.sessionChanged) rethrow;
    }
  }

  Future<void> _unblock(String id) async {
    if (vault.hasRetainedCiphertext(id)) return;
    await store.update(
      (state) => LocalSyncState(
        accountUserId: state.accountUserId,
        notes: state.notes,
        conflicts: state.conflicts,
        cursor: state.cursor,
        outbox: state.outbox.map(
          (m) =>
              m.noteId == id &&
                  m.blocked &&
                  (m.lastError == null ||
                      m.lastError == SyncErrorCode.forbidden)
              ? _unblocked(m)
              : m,
        ),
      ),
    );
  }

  void _activate(String id, NoteUnlockLease lease, {required bool online}) {
    if (!lease.expiresAt.isAfter(_now())) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.expired);
    }
    _knownProtection[id] = lease.protection;
    _access[id] = (
      protection: lease.protection,
      operations: lease.operations,
      expiresAt: lease.expiresAt,
      session: _capture(),
      online: online,
    );
    _timers.remove(id)?.cancel();
    _timers[id] = Timer(lease.expiresAt.difference(_now()), () => lock(id));
    if (!_changes.isClosed) _changes.add(null);
  }

  void lock(String? id) {
    _generation++;
    if (id == null) {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
      _access.clear();
    } else {
      _timers.remove(id)?.cancel();
      _access.remove(id);
    }
    gateway.invalidate(id);
    vault.lock(id);
    cancelSummaries?.call();
    if (!_changes.isClosed) _changes.add(null);
  }

  bool retainedPending(String id) => vault.hasRetainedCiphertext(id);
  void dispose() {
    if (_disposed) return;
    lock(null);
    _disposed = true;
    unawaited(_changes.close());
  }

  static void _confirm(String password, String confirmation) {
    if (password != confirmation ||
        password.length < 8 ||
        password.length > 512) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.invalidInput);
    }
  }

  static PendingMutation _unblocked(PendingMutation m) => PendingMutation(
    mutationId: m.mutationId,
    noteId: m.noteId,
    operation: m.operation,
    baseRevision: m.baseRevision,
    payload: m.payload,
    createdAt: m.createdAt,
    retryCount: m.retryCount,
    blocked: false,
  );
}
