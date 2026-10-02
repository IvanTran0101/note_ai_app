part of 'encrypted_state_codec.dart';

/// Move legacy lookup keys without relabeling their authenticated ciphertext.
extension EncryptedLegacyBindings on EncryptedStateCodec {
  void _normalizeLegacyBindings(Map<String, Object?> state) {
    for (final note in NoteBundleProjection.notes(state)) {
      if (note['ownerId'] != namespace.accountUserId) continue;
      final oldId = note['id'] as String;
      final reference = NoteBundleProjection.reference(state, note);
      if (oldId == reference) continue;
      final oldRecord = _records[oldId] as Map?;
      if (oldRecord != null && oldRecord['binding'] == null) {
        if (_records.containsKey(reference)) {
          throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
        }
        _records[reference] = {...oldRecord, 'binding': oldId};
        _records.remove(oldId);
        migrationRequired = true;
      }
      final oldQuarantine = _quarantine[oldId] as Map?;
      if (oldQuarantine != null && oldQuarantine['binding'] == null) {
        if (_quarantine.containsKey(reference)) {
          throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
        }
        _quarantine[reference] = {'binding': oldId, 'packet': oldQuarantine};
        _quarantine.remove(oldId);
        migrationRequired = true;
      }
    }
  }

  Object? _quarantinePacket(String id) {
    final record = _quarantine[id] as Map?;
    return record?.containsKey('binding') == true ? record!['packet'] : record;
  }
}
