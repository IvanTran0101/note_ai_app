part of 'encrypted_sync_store.dart';

/// One CAS includes wrapped keys, ciphertext, local metadata and sync intent.
extension EncryptedLocalProtection on EncryptedSyncStore {
  Future<NoteProtection> _localProtection(
    String id,
    String? current,
    String? password, {
    required bool enable,
  }) => _enqueue(() async {
    NoteProtection? result;
    await _mutate((state) async {
      final note = state.notes
          .where(
            (n) =>
                n.id == id && n.ownerId == state.accountUserId && !n.isDeleted,
          )
          .firstOrNull;
      if (note == null) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
      }
      if (current == null &&
              (note.protection.enabled || !note.contentAvailable) ||
          current != null && !note.protection.enabled) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.invalidInput);
      }
      if (state.conflicts.any((c) => c.identity == note.identity)) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.pendingSync);
      }
      final next = NoteProtection(
        enabled: enable,
        revision: note.protection.revision + 1,
      );
      final verifier = password == null
          ? null
          : await codec.crypto.passwordVerifier(password);
      final sealed = current == null
          ? await codec.seal(state, id, password!, next)
          : enable
          ? await codec.rewrap(state, id, current, password!, next)
          : await codec.disable(state, id, current, next);
      result = next;
      return LocalProtectionQueue.apply(
        state,
        note,
        sealed,
        ProtectionSyncChange(
          before: note.protection,
          after: next,
          verifier: verifier,
        ),
        base64UrlEncode(codec.crypto.randomBytes(24)),
        DateTime.now().toUtc(),
      );
    });
    return result!;
  });
}
