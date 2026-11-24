/// Encrypted binary storage only. It is not another Note writer/outbox/cursor.
/// The small index transaction reserves quota atomically across concurrent jobs.
abstract interface class AttachmentBlobStore {
  Future<Map<String, Object?>> readIndex();
  Future<Map<String, Object?>> updateIndex(
    Map<String, Object?> Function(Map<String, Object?> current) change,
  );
  Future<Map<String, Object?>?> readChunk(String key);
  Future<void> writeChunk(String key, Map<String, Object?> encryptedPacket);
  Future<void> removeChunk(String key);
}

String checkedAttachmentRecordKey(String key) {
  if (!RegExp(r'^[a-f0-9]{64}-(?:meta|[0-9]{3})$').hasMatch(key)) {
    throw ArgumentError('Invalid binary record key.');
  }
  return key;
}
