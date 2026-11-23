part of 'encrypted_attachment_cache.dart';

extension _AttachmentCacheReadOps on EncryptedAttachmentCache {
  Stream<List<int>> _readChunks(
    AttachmentBinding binding,
    LocalAttachmentDraft draft,
    int start,
    int end, {
    NoteOperation operation = NoteOperation.attachmentRead,
  }) async* {
    _require(binding, operation);
    if (draft.sizeBytes <= 0 ||
        draft.sizeBytes > 50 * AttachmentPolicy.mib ||
        draft.chunkCount !=
            (draft.sizeBytes + AttachmentPolicy.chunkBytes - 1) ~/
                AttachmentPolicy.chunkBytes) {
      throw const FormatException('Invalid attachment chunk manifest.');
    }
    if (start < 0 || end < start || end > draft.sizeBytes) {
      throw RangeError('Invalid attachment range.');
    }
    for (
      var chunk = start ~/ AttachmentPolicy.chunkBytes;
      chunk < draft.chunkCount && chunk * AttachmentPolicy.chunkBytes < end;
      chunk++
    ) {
      _require(binding, operation);
      final index = await store.readIndex();
      _require(binding, operation);
      final record = index[draft.cacheId];
      final phases = operation == NoteOperation.attachmentWrite
          ? const {'staging', 'queued', 'linked'}
          : const {'queued', 'linked'};
      if (record is! Map ||
          record['scope'] != _scope(binding) ||
          record['sizeBytes'] != draft.sizeBytes ||
          (record['phase'] != 'staging' &&
              record['chunkCount'] != draft.chunkCount) ||
          !phases.contains(record['phase'])) {
        throw StateError('Attachment was cancelled or is unavailable.');
      }
      final packet = await store.readChunk(_chunk(draft.cacheId, chunk));
      _require(binding, operation);
      if (packet == null) {
        throw StateError('Encrypted attachment chunk is missing.');
      }
      final plaintext = await cipher.open(
        binding,
        draft.cacheId,
        chunk,
        packet,
        operation: operation,
      );
      try {
        final base = chunk * AttachmentPolicy.chunkBytes;
        final expected = draft.sizeBytes - base < AttachmentPolicy.chunkBytes
            ? draft.sizeBytes - base
            : AttachmentPolicy.chunkBytes;
        if (plaintext.length != expected) {
          throw const FormatException('Invalid encrypted attachment size.');
        }
        final from = start > base ? start - base : 0;
        final to = end < base + plaintext.length
            ? end - base
            : plaintext.length;
        _require(binding, operation);
        // Returned chunks belong to the consumer; its preview/transport must
        // release them on cancellation. The cache's decrypted buffer is wiped.
        yield Uint8List.fromList(plaintext.sublist(from, to));
      } finally {
        plaintext.fillRange(0, plaintext.length, 0);
      }
    }
  }

  Future<void> _removeStaging(String id, int count) async {
    for (var chunk = 0; chunk < count; chunk++) {
      await store.removeChunk(_chunk(id, chunk));
    }
    await store.removeChunk('$id-meta');
    await store.updateIndex((index) => {...index}..remove(id));
  }
}
