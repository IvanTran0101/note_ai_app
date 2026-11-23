part of 'encrypted_state_codec.dart';

/// Binary DEK has its own durable wrap. Password changes only rewrap it in the
/// same account CAS, so offline Pending bytes do not depend on a retired epoch.
extension EncryptedAttachmentKeys on EncryptedStateCodec {
  bool hasAttachmentKey(AttachmentBinding binding) =>
      _binaryKeys.containsKey(binding.note.referenceFor(binding.actorId));
  String _binaryAad(String reference, NoteProtection protection) =>
      '$_accountAad/binary-key/${jsonEncode(reference)}/${protection.enabled}/${protection.revision}';

  Future<SecretKey> attachmentKey(AttachmentBinding binding) async {
    final reference = binding.note.referenceFor(binding.actorId);
    final root = await attachmentRootKey(binding);
    final start = generation;
    final raw = _binaryKeys[reference];
    if (raw == null) {
      final key = await crypto.newKey();
      try {
        await _wrapBinary(reference, binding.protection, root, key);
        if (start != generation) {
          throw const NoteSecurityFailure(
            NoteSecurityFailureCode.sessionChanged,
          );
        }
        _binaryOpened.remove(reference)?.destroy();
        _binaryOpened[reference] = key;
        return key;
      } on Object {
        key.destroy();
        rethrow;
      }
    }
    final record = Map<String, Object?>.from(raw as Map);
    if (record.length != 3 ||
        record['enabled'] != binding.protection.enabled ||
        record['revision'] != binding.protection.revision) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.staleRevision);
    }
    final cached = _binaryOpened[reference];
    if (cached != null) return cached;
    final bytes = await crypto.decrypt(
      record['wrapped'],
      root,
      _binaryAad(reference, binding.protection),
    );
    try {
      if (bytes.length != 32 || start != generation) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
      }
      final key = SecretKeyData(List.of(bytes), overwriteWhenDestroyed: true);
      _binaryOpened[reference] = key;
      return key;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<void> _wrapBinary(
    String reference,
    NoteProtection p,
    SecretKey root,
    SecretKey key,
  ) async {
    final bytes = List<int>.of(await key.extractBytes());
    try {
      _binaryKeys[reference] = {
        'enabled': p.enabled,
        'revision': p.revision,
        'wrapped': await crypto.encrypt(bytes, root, _binaryAad(reference, p)),
      };
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<void> _rewrapBinary(
    String reference,
    NoteProtection before,
    NoteProtection after,
    SecretKey? previousRoot,
    SecretKey nextRoot,
  ) async {
    final raw = _binaryKeys[reference];
    if (raw == null) return;
    final record = Map<String, Object?>.from(raw as Map);
    // Remote reset/new device: preserve the old wrap/ciphertext for explicit
    // recovery. Never silently relabel it or substitute the device key.
    if (previousRoot == null ||
        record['enabled'] != before.enabled ||
        record['revision'] != before.revision) {
      return;
    }
    final plain = await crypto.decrypt(
      record['wrapped'],
      previousRoot,
      _binaryAad(reference, before),
    );
    final key = SecretKeyData(List.of(plain), overwriteWhenDestroyed: true);
    try {
      await _wrapBinary(reference, after, nextRoot, key);
    } finally {
      plain.fillRange(0, plain.length, 0);
      key.destroy();
      _binaryOpened.remove(reference)?.destroy();
    }
  }
}
