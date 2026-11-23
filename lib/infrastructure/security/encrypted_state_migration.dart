part of 'encrypted_state_codec.dart';

extension _EncryptedStateMigration on EncryptedStateCodec {
  Future<LocalSyncState> _migrate(Map<String, Object?> old) async {
    final decoded = LocalSyncStateCodec.decode(
      NoteBundleProjection.migrateV2(old),
    );
    namespace.requireOwned(decoded);
    // Redaction adds current manifest fields; normalize before quarantining so
    // subsequent decoding does not mistake them for an invalid legacy record.
    final state = LocalSyncStateCodec.encode(decoded);
    if (decoded.notes.length > 10000 ||
        decoded.outbox.length > 10000 ||
        decoded.conflicts.length > 10000) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
    }
    await _ensureDeviceKey();
    _records = {};
    _quarantine = {};
    _retained = {};
    _binaryKeys = {};
    for (final note in decoded.notes) {
      _quarantine[note.referenceFor(namespace.accountUserId)] = await crypto
          .encryptJson(
            NoteBundleProjection.bundle(
              state,
              note.referenceFor(namespace.accountUserId),
            ),
            _deviceKey!,
            _legacyAad(note.referenceFor(namespace.accountUserId)),
          );
      NoteBundleProjection.redact(
        state,
        note.referenceFor(namespace.accountUserId),
      );
    }
    migrationRequired = true;
    return LocalSyncStateCodec.decode(state);
  }
}
