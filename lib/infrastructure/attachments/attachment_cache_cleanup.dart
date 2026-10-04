part of 'encrypted_attachment_cache.dart';

extension _AttachmentCacheCleanup on EncryptedAttachmentCache {
  int _maxChunks(Map record) =>
      ((record['sizeBytes'] as int) + AttachmentPolicy.chunkBytes - 1) ~/
      AttachmentPolicy.chunkBytes;
  Future<void> _upgradeLegacyPackets(
    AttachmentBinding binding,
  ) => _serialized(() async {
    _require(binding, NoteOperation.attachmentRead);
    final index = await store.readIndex();
    for (final entry in index.entries) {
      final r = entry.value as Map;
      if (r['scope'] != _scope(binding) ||
          !{'queued', 'linked', 'remote'}.contains(r['phase'])) {
        continue;
      }
      final keys = [
        for (var i = 0; i < (r['chunkCount'] as int); i++) _chunk(entry.key, i),
        '${entry.key}-meta',
      ];
      for (final recordKey in keys) {
        final packet = await store.readChunk(recordKey);
        if (packet == null) continue;
        final chunk = recordKey.endsWith('-meta')
            ? -1
            : int.parse(recordKey.split('-').last);
        final bytes = await cipher.open(binding, entry.key, chunk, packet);
        try {
          // The binary DEK is durably stored before this overwrite. On a crash,
          // both v1 and v2 packets remain readable under the original Note epoch.
          final sealed = await cipher.seal(
            binding,
            entry.key,
            chunk,
            bytes,
            operation: NoteOperation.attachmentRead,
          );
          _require(binding, NoteOperation.attachmentRead);
          await store.writeChunk(recordKey, sealed);
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      }
    }
  });
  Future<void> _markCancelling(
    String id,
    String scope, {
    AttachmentBinding? binding,
  }) async {
    await store.updateIndex((index) {
      if (binding != null) _require(binding, NoteOperation.attachmentWrite);
      final record = index[id];
      if (record is! Map ||
          record['scope'] != scope ||
          record['phase'] == 'linked') {
        throw StateError('Only an unlinked attachment can be cancelled.');
      }
      return {
        ...index,
        id: {...record, 'phase': 'cancelling'},
      };
    });
  }
}
