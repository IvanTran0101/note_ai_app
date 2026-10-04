part of 'encrypted_state_codec.dart';

/// Password wrapping and transient per-note keys have one owner.
extension EncryptedStateKeys on EncryptedStateCodec {
  LocalNoteState _requireLocalRead(LocalSyncState state, String reference) {
    final note = state.notes
        .where((n) => n.referenceFor(namespace.accountUserId) == reference)
        .firstOrNull;
    if (note == null ||
        note.ownerId != namespace.accountUserId &&
            note.share?.isActive != true) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
    }
    return note;
  }

  LocalNoteState _requireLocalOwner(LocalSyncState state, String reference) {
    final note = _requireLocalRead(state, reference);
    if (note.ownerId != namespace.accountUserId) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
    }
    return note;
  }

  Future<LocalSyncState> unlock(
    LocalSyncState state,
    String id,
    String password,
    NoteProtection p, {
    required bool verifiedOnline,
  }) async {
    _requireLocalRead(state, id);
    if (!p.enabled) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.invalidInput);
    }
    final start = generation;
    final old = _records[id] == null
        ? null
        : Map<String, Object?>.from(_records[id] as Map);
    if (old != null && old['epoch'] == p.revision) {
      final kek = await crypto.passwordKey(
        password,
        base64Decode(old['salt'] as String),
      );
      try {
        final bytes = await crypto.decrypt(
          old['wrapped'],
          kek,
          '${_noteAad(id, p.revision)}/key',
        );
        try {
          if (bytes.length != 32) {
            throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
          }
          final key = SecretKeyData(
            List<int>.of(bytes),
            overwriteWhenDestroyed: true,
          );
          if (start != generation) {
            key.destroy();
            throw const NoteSecurityFailure(
              NoteSecurityFailureCode.sessionChanged,
            );
          }
          _opened.remove(id)?.key.destroy();
          _opened[id] = (key: key, epoch: p.revision);
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      } on NoteSecurityFailure catch (failure) {
        if (failure.code == NoteSecurityFailureCode.storage) {
          throw const NoteSecurityFailure(
            NoteSecurityFailureCode.invalidPassword,
          );
        }
        rethrow;
      } finally {
        kek.destroy();
      }
      final data = LocalSyncStateCodec.encode(state);
      NoteBundleProjection.restore(
        data,
        await crypto.decryptJson(
          old['box'],
          _opened[id]!.key,
          _noteAad(id, p.revision),
        ),
        requireCurrentRevision: true,
      );
      return LocalSyncStateCodec.decode(data);
    }
    if (!verifiedOnline) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
    }
    if (old != null) {
      final records = List<Object?>.of((_retained[id] as List?) ?? []);
      records.add(old);
      _retained[id] = records;
    }
    var next = state;
    if (_quarantine.containsKey(id)) {
      final data = LocalSyncStateCodec.encode(state);
      NoteBundleProjection.restore(
        data,
        await crypto.decryptJson(
          _quarantinePacket(id),
          _deviceKey!,
          _legacyAad(id),
        ),
      );
      next = LocalSyncStateCodec.decode(data);
      _quarantine.remove(id);
    }
    return seal(next, id, password, p, recipientUnlock: true);
  }

  Future<LocalSyncState> seal(
    LocalSyncState state,
    String id,
    String password,
    NoteProtection p, {
    bool recipientUnlock = false,
  }) async {
    final note = _requireLocalRead(state, id);
    if (!recipientUnlock && note.ownerId != namespace.accountUserId) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
    }
    if (!p.enabled) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.invalidInput);
    }
    final start = generation;
    final key = await crypto.newKey();
    try {
      await _ensureDeviceKey();
      await _rewrapBinary(
        id,
        note.protection,
        p,
        note.protection.enabled ? _opened[id]?.key : _deviceKey,
        key,
      );
      await _wrap(id, password, p, key);
      if (start != generation) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
      }
      _opened.remove(id)?.key.destroy();
      _opened[id] = (key: key, epoch: p.revision);
      return EncryptedStateCodec.changeMetadata(state, id, p);
    } on Object {
      key.destroy();
      rethrow;
    }
  }

  Future<LocalSyncState> rewrap(
    LocalSyncState state,
    String id,
    String currentPassword,
    String newPassword,
    NoteProtection p,
  ) async {
    final oldNote = _requireLocalOwner(state, id);
    final decoded = await unlock(
      state,
      id,
      currentPassword,
      oldNote.protection,
      verifiedOnline: false,
    );
    final key = _opened[id]!.key;
    final start = generation;
    await _rewrapBinary(id, oldNote.protection, p, key, key);
    await _wrap(id, newPassword, p, key);
    if (start != generation) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
    _opened[id] = (key: key, epoch: p.revision);
    return EncryptedStateCodec.changeMetadata(decoded, id, p);
  }

  Future<void> _wrap(
    String id,
    String password,
    NoteProtection p,
    SecretKey key,
  ) async {
    final binding = (_records[id] as Map?)?['binding'] ?? id;
    final salt = crypto.randomBytes(16);
    final kek = await crypto.passwordKey(password, salt);
    final bytes = List<int>.of(await key.extractBytes());
    try {
      _records[id] = {
        'epoch': p.revision,
        'binding': binding,
        'salt': base64Encode(salt),
        'wrapped': await crypto.encrypt(
          bytes,
          kek,
          '${_noteAad(id, p.revision)}/key',
        ),
      };
    } finally {
      kek.destroy();
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<LocalSyncState> disable(
    LocalSyncState state,
    String id,
    String password,
    NoteProtection p,
  ) async {
    final old = _requireLocalOwner(state, id);
    final decoded = await unlock(
      state,
      id,
      password,
      old.protection,
      verifiedOnline: false,
    );
    await _ensureDeviceKey();
    await _rewrapBinary(id, old.protection, p, _opened[id]?.key, _deviceKey!);
    _records.remove(id);
    lock(id);
    return EncryptedStateCodec.changeMetadata(decoded, id, p);
  }
}
