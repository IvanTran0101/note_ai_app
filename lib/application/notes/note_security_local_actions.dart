part of 'note_security_service.dart';

extension LocalNoteSecurityActions on NoteSecurityService {
  Future<bool> _tryLocalUnlock(
    String id,
    String password,
    NoteProtection p,
    bool offline,
  ) async {
    try {
      await vault.unlock(id, password, p);
      return true;
    } on NoteSecurityFailure catch (failure) {
      // No cached key on a new device: provision only through online authority.
      // Wrong password/tampered ciphertext never falls back to cloud.
      if (localFirst &&
          !offline &&
          failure.code == NoteSecurityFailureCode.locked &&
          !await hasPendingProtection(id)) {
        return false;
      }
      rethrow;
    }
  }

  ILocalFirstNoteVault get _localVault {
    final adapter = vault;
    if (adapter is! ILocalFirstNoteVault) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
    }
    return adapter as ILocalFirstNoteVault;
  }

  void _localLease(String id, NoteProtection p) {
    _generation++;
    _activate(
      id,
      NoteUnlockLease(
        protection: p,
        operations: NoteOperation.values.toSet(),
        expiresAt: _now().add(const Duration(minutes: 15)),
      ),
      online: false,
    );
  }

  Future<void> _enableLocal(String id, String password) async {
    final captured = _capture(), generation = _generation;
    final next = await _localVault.enableLocal(id, password);
    _live(captured, generation);
    cancelSummaries?.call();
    _localLease(id, next);
    _launchSync(id, null, password);
  }

  Future<void> _changeLocal(String id, String current, String next) async {
    final captured = _capture(), generation = _generation;
    final p = await _localVault.changeLocal(id, current, next);
    _live(captured, generation);
    cancelSummaries?.call();
    _localLease(id, p);
    _launchSync(id, current, next);
  }

  Future<void> _disableLocal(String id, String current) async {
    final captured = _capture(), generation = _generation;
    final p = await _localVault.disableLocal(id, current);
    _live(captured, generation);
    _knownProtection[id] = p;
    lock(id);
    _launchSync(id, current, null);
  }

  Future<bool> hasPendingProtection(String id) async =>
      (await store.read()).outbox.any(
        (m) =>
            m.noteId == id &&
            m.mutation.identityFor(accountId).ownerId == accountId &&
            m.protectionChange != null,
      );

  /// A cloud password is transient. It never replaces the local password/key.
  Future<void> authorizePendingSync(String id, String cloudPassword) async {
    final captured = _capture(), generation = _generation;
    final note = await _note(id);
    requireAccess(
      ownerId: accountId,
      noteId: id,
      protection: note.protection,
      operation: NoteOperation.manage,
    );
    final state = await store.read();
    _live(captured, generation);
    final change = state.outbox
        .where(
          (m) =>
              m.noteId == id &&
              m.mutation.identityFor(accountId).ownerId == accountId &&
              m.protectionChange != null,
        )
        .firstOrNull
        ?.protectionChange;
    if (change == null) return;
    if (change.before.enabled) {
      final lease = await gateway.unlock(id, cloudPassword, {
        NoteOperation.manage,
        NoteOperation.read,
        NoteOperation.edit,
        NoteOperation.delete,
      });
      _live(captured, generation);
      if (lease.protection != change.before) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.staleRevision);
      }
    }
    await _unblock(id);
    _live(captured, generation);
    await syncNow?.call();
    _live(captured, generation);
  }

  void _launchSync(String id, String? cloudPassword, String? localPassword) {
    final captured = _capture(), generation = _generation;
    // Function-local secrets survive only this bounded attempt, never retries.
    unawaited(() async {
      try {
        if (!await _authorizePredecessor(
          id,
          cloudPassword,
          captured,
          generation,
        )) {
          return;
        }
        await _syncAndRefresh(id, localPassword, captured, generation);
      } on Object {
        // Local success stands. The durable outbox owns errors and later sync.
      }
    }());
  }

  Future<bool> _authorizePredecessor(
    String id,
    String? cloudPassword,
    int captured,
    int generation,
  ) async {
    final state = await store.read();
    _live(captured, generation);
    final shared = state.notes
        .where((n) => n.referenceFor(accountId) == id && n.ownerId != accountId)
        .firstOrNull;
    if (shared != null) {
      if (!shared.share!.isActive || cloudPassword == null) return false;
      final lease = await gateway.unlock(id, cloudPassword, {
        NoteOperation.read,
        NoteOperation.summary,
        if (shared.share!.role.name == 'editor') NoteOperation.edit,
      });
      _live(captured, generation);
      return lease.protection == shared.protection;
    }
    final change = state.outbox
        .where(
          (m) =>
              m.noteId == id &&
              m.mutation.identityFor(accountId).ownerId == accountId &&
              m.protectionChange != null,
        )
        .firstOrNull
        ?.protectionChange;
    final local = state.notes
        .where((n) => n.id == id && n.ownerId == accountId)
        .firstOrNull;
    final remoteProtection = change?.before ?? local?.protection;
    if (remoteProtection?.enabled == true &&
        !gateway.hasAuthority(id, remoteProtection!, NoteOperation.manage)) {
      if (cloudPassword == null) return false;
      final lease = await gateway.unlock(id, cloudPassword, {
        NoteOperation.read,
        NoteOperation.edit,
        NoteOperation.delete,
        NoteOperation.manage,
      });
      _live(captured, generation);
      if (lease.protection != remoteProtection) return false;
    }
    return true;
  }

  Future<void> _syncAndRefresh(
    String id,
    String? localPassword,
    int captured,
    int generation,
  ) async {
    await _unblock(id);
    _live(captured, generation);
    await syncNow?.call();
    _live(captured, generation);
    final note = (await store.read()).notes
        .where((n) => n.id == id && n.ownerId == accountId)
        .firstOrNull;
    if (await hasPendingProtection(id) ||
        note?.protection.enabled != true ||
        localPassword == null) {
      return;
    }
    final lease = await gateway.unlock(
      id,
      localPassword,
      NoteOperation.values.toSet(),
    );
    _live(captured, generation);
    if (lease.protection != note!.protection) return;
    await _unblock(id);
    _live(captured, generation);
    await syncNow?.call();
  }
}
