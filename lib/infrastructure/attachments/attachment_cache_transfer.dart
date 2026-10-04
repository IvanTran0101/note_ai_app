part of 'encrypted_attachment_cache.dart';

extension _AttachmentTransferCacheOps on EncryptedAttachmentCache {
  Future<bool> linkedState(AttachmentBinding binding, String id) async {
    _require(binding, NoteOperation.attachmentRead);
    final index = await store.readIndex();
    _require(binding, NoteOperation.attachmentRead);
    final record = index[id];
    return record is Map &&
        record['scope'] == _scope(binding) &&
        record['phase'] == 'linked';
  }

  Future<void> queueCancelState(AttachmentBinding binding, String id) =>
      _serialized(() async {
        _require(binding, NoteOperation.attachmentWrite);
        checkedAttachmentRecordKey('$id-meta');
        await store.updateIndex((index) {
          _require(binding, NoteOperation.attachmentWrite);
          final record = index[id];
          if (record is! Map ||
              record['scope'] != _scope(binding) ||
              record['phase'] == 'linked') {
            throw StateError('Invalid cancellation.');
          }
          return {
            ...index,
            id: {...record, 'phase': 'remoteCancelling'},
          };
        });
        for (var chunk = 0; chunk < 200; chunk++) {
          await store.removeChunk(_chunk(id, chunk));
        }
        await store.removeChunk('$id-meta');
        _require(binding, NoteOperation.attachmentWrite);
      });
  Future<List<String>> cancelStateIds(AttachmentBinding binding) async {
    _require(binding, NoteOperation.attachmentWrite);
    final index = await store.readIndex();
    _require(binding, NoteOperation.attachmentWrite);
    return index.entries
        .where(
          (e) =>
              (e.value as Map)['scope'] == _scope(binding) &&
              (e.value as Map)['phase'] == 'remoteCancelling',
        )
        .map((e) => e.key)
        .toList();
  }

  Future<void> finishCancelState(AttachmentBinding binding, String id) =>
      _serialized(() async {
        _require(binding, NoteOperation.attachmentWrite);
        final index = await store.readIndex();
        final entry = index[id];
        if (entry is! Map ||
            entry['scope'] != _scope(binding) ||
            entry['phase'] != 'remoteCancelling') {
          throw StateError('Invalid cancellation ACK.');
        }
        await _removeStaging(id, 200);
        _require(binding, NoteOperation.attachmentWrite);
      });
  Stream<List<int>> readAssociatedChunks(
    AttachmentBinding binding,
    Attachment attachment,
    ReadRemoteAttachment remote, {
    int start = 0,
    int? end,
  }) async* {
    _require(binding, NoteOperation.attachmentRead);
    if (attachment.noteId != binding.note.noteId) {
      throw StateError('Invalid binary association.');
    }
    final stop = end ?? attachment.sizeBytes;
    if (start < 0 || stop < start || stop > attachment.sizeBytes) {
      throw RangeError('Invalid attachment range.');
    }
    final id = attachment.id, scope = _scope(binding);
    // Reserve full-file quota even for a sparse download; no unbounded partial entries.
    await _serialized(
      () => store.updateIndex((index) {
        _require(binding, NoteOperation.attachmentRead);
        final entry = index[id];
        if (entry is Map) {
          if (entry['scope'] != scope ||
              entry['sizeBytes'] != attachment.sizeBytes ||
              !{'queued', 'linked', 'remote'}.contains(entry['phase'])) {
            throw StateError('Invalid binary cache association.');
          }
          return index;
        }
        final used = index.values.fold<int>(
          0,
          (n, r) => n + ((r as Map)['sizeBytes'] as int),
        );
        if (used + attachment.sizeBytes > AttachmentPolicy.maxCacheBytes) {
          throw StateError('Encrypted cache quota exceeded.');
        }
        return {
          ...index,
          id: {
            'scope': scope,
            'sizeBytes': attachment.sizeBytes,
            'chunkCount':
                (attachment.sizeBytes + AttachmentPolicy.chunkBytes - 1) ~/
                AttachmentPolicy.chunkBytes,
            'phase': 'remote',
          },
        };
      }),
    );
    for (
      var i = start ~/ AttachmentPolicy.chunkBytes;
      i * AttachmentPolicy.chunkBytes < stop;
      i++
    ) {
      final base = i * AttachmentPolicy.chunkBytes;
      final chunkEnd = (base + AttachmentPolicy.chunkBytes).clamp(
        0,
        attachment.sizeBytes,
      );
      Uint8List? bytes;
      try {
        final packet = await store.readChunk(_chunk(id, i));
        _require(binding, NoteOperation.attachmentRead);
        if (packet != null) {
          try {
            bytes = await cipher.open(binding, id, i, packet);
          } on Object {
            _require(binding, NoteOperation.attachmentRead);
          }
        }
        if (bytes == null) {
          bytes = Uint8List(chunkEnd - base);
          var offset = 0;
          await for (final part in remote(
            binding,
            attachment,
            start: base,
            end: chunkEnd,
          )) {
            try {
              _require(binding, NoteOperation.attachmentRead);
              if (offset + part.length > bytes.length) {
                throw StateError('Invalid remote byte range.');
              }
              bytes.setRange(offset, offset + part.length, part);
              offset += part.length;
            } finally {
              part.fillRange(0, part.length, 0);
            }
          }
          if (offset != bytes.length) {
            throw StateError('Incomplete remote chunk.');
          }
          final packet = await cipher.seal(
            binding,
            id,
            i,
            bytes,
            operation: NoteOperation.attachmentRead,
          );
          _require(binding, NoteOperation.attachmentRead);
          await store.writeChunk(_chunk(id, i), packet);
        }
        _require(binding, NoteOperation.attachmentRead);
        if (bytes.length != chunkEnd - base) {
          throw StateError('Invalid cached byte range.');
        }
        yield Uint8List.fromList(
          bytes.sublist(
            (start - base).clamp(0, bytes.length),
            (stop - base).clamp(0, bytes.length),
          ),
        );
      } finally {
        bytes?.fillRange(0, bytes.length, 0);
      }
    }
    _require(binding, NoteOperation.attachmentRead);
  }
}

final class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest data) {
    value = data;
  }

  @override
  void close() {}
}
