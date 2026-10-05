part of 'note_security_service.dart';

/// Password actions coordinate remote authority with the durable local vault.
extension NoteSecurityActions on NoteSecurityService {
  Future<void> unlock(
    String id,
    String password, {
    bool offline = false,
  }) async {
    final captured = _capture(), generation = _generation;
    try {
      final note = await _note(id);
      _live(captured, generation);
      if ((offline || localFirst) &&
          await _tryLocalUnlock(id, password, note.protection, offline)) {
        _live(captured, generation);
        if (!(await _note(id)).contentAvailable) {
          throw const NoteSecurityFailure(
            NoteSecurityFailureCode.staleRevision,
          );
        }
        _live(captured, generation);
        _activate(
          id,
          NoteUnlockLease(
            protection: note.protection,
            operations: {
              NoteOperation.read,
              NoteOperation.edit,
              NoteOperation.delete,
              NoteOperation.summary,
              NoteOperation.attachmentRead,
              if (note.ownerId == accountId) NoteOperation.attachmentWrite,
              if (localFirst) NoteOperation.manage,
              if (localFirst) NoteOperation.export,
            },
            expiresAt: _now().add(const Duration(minutes: 15)),
          ),
          online: false,
        );
        if (localFirst && !offline) _launchSync(id, password, password);
        return;
      }
      final p = await gateway.metadata(id);
      _live(captured, generation);
      _knownProtection[id] = p;
      await vault.observeProtection(id, p);
      _live(captured, generation);
      final lease = await gateway.unlock(id, password, {
        NoteOperation.read,
        if (note.ownerId == accountId || note.share?.role.name == 'editor')
          NoteOperation.edit,
        if (note.ownerId == accountId) NoteOperation.delete,
        if (note.ownerId == accountId) NoteOperation.manage,
        NoteOperation.summary,
        NoteOperation.attachmentRead,
        if (note.ownerId == accountId) NoteOperation.attachmentWrite,
        if (note.ownerId == accountId) NoteOperation.export,
      });
      _live(captured, generation);
      await vault.unlock(id, password, lease.protection, verifiedOnline: true);
      _live(captured, generation);
      await _hydrateAuthorized(id, lease.protection);
      _live(captured, generation);
      _activate(id, lease, online: true);
      await _unblock(id);
    } on Object {
      lock(id);
      rethrow;
    }
  }

  Future<void> enable(String id, String password, String confirmation) async {
    await _ownerAction(id);
    NoteSecurityService._confirm(password, confirmation);
    if (localFirst) return _enableLocal(id, password);
    final captured = _capture(), generation = _generation;
    await syncNow?.call();
    _live(captured, generation);
    final p = await gateway.metadata(id);
    _knownProtection[id] = p;
    await vault.observeProtection(id, p);
    final note = await _note(id);
    final state = await store.read();
    _live(captured, generation);
    if (p.enabled ||
        !note.contentAvailable ||
        note.serverRevision < 1 ||
        state.outbox.any((m) => m.noteId == id) ||
        state.conflicts.any((c) => c.noteId == id)) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.pendingSync);
    }
    final next = NoteProtection(enabled: true, revision: p.revision + 1);
    try {
      await vault.seal(id, password, next);
      _live(captured, generation);
      final remote = await gateway.enable(id, password, note.serverRevision);
      _live(captured, generation);
      if (remote != next) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.staleRevision);
      }
    } on Object {
      lock(id);
      rethrow;
    }
    await unlock(id, password);
  }

  Future<void> changePassword(
    String id,
    String currentPassword,
    String newPassword,
    String confirmation,
  ) async {
    NoteSecurityService._confirm(newPassword, confirmation);
    await _ownerAction(id);
    if (localFirst) return _changeLocal(id, currentPassword, newPassword);
    final captured = _capture(), generation = _generation;
    final note = await _note(id);
    requireRemote(id, note.protection, NoteOperation.manage);
    var remoteChanged = false;
    try {
      final next = await gateway.change(
        id,
        currentPassword,
        newPassword,
        note.protection.revision,
      );
      remoteChanged = true;
      _live(captured, generation);
      await vault.rewrap(id, currentPassword, newPassword, next);
      _live(captured, generation);
    } on NoteSecurityFailure catch (failure) {
      // A rejected verifier changed neither side; keep the live grant so the
      // current-password form can be corrected. Any ambiguous/partial change
      // still clears authority and requires a fresh unlock.
      if (remoteChanged ||
          failure.code != NoteSecurityFailureCode.invalidPassword) {
        lock(id);
      }
      rethrow;
    } on Object {
      lock(id);
      rethrow;
    }
    lock(id);
    await unlock(id, newPassword);
  }

  Future<void> disable(String id, String currentPassword) async {
    await _ownerAction(id);
    if (localFirst) return _disableLocal(id, currentPassword);
    final captured = _capture(), generation = _generation;
    final note = await _note(id);
    requireRemote(id, note.protection, NoteOperation.manage);
    var remoteChanged = false;
    try {
      final next = await gateway.disable(
        id,
        currentPassword,
        note.protection.revision,
      );
      remoteChanged = true;
      _live(captured, generation);
      _knownProtection[id] = next;
      await vault.disable(id, currentPassword, next);
      _live(captured, generation);
    } on NoteSecurityFailure catch (failure) {
      if (remoteChanged ||
          failure.code != NoteSecurityFailureCode.invalidPassword) {
        lock(id);
      }
      rethrow;
    } on Object {
      lock(id);
      rethrow;
    }
    lock(id);
  }

  Future<NoteRecoveryChallenge> requestRecovery(String id) async {
    await _ownerAction(id);
    final captured = _capture(), generation = _generation;
    final challenge = await gateway.requestRecovery(id);
    _live(captured, generation);
    return challenge;
  }

  Future<void> confirmRecovery(
    String id,
    String challengeId,
    String code,
    String password,
    String confirmation,
  ) async {
    NoteSecurityService._confirm(password, confirmation);
    await _ownerAction(id);
    final captured = _capture(), generation = _generation;
    final lease = await gateway.confirmRecovery(
      id,
      challengeId,
      code,
      password,
    );
    _live(captured, generation);
    try {
      await vault.observeProtection(id, lease.protection);
      await vault.unlock(id, password, lease.protection, verifiedOnline: true);
      _live(captured, generation);
      await _hydrateAuthorized(id, lease.protection);
      _live(captured, generation);
      _activate(id, lease, online: true);
      await _unblock(id);
    } on Object {
      lock(id);
      rethrow;
    }
  }
}
