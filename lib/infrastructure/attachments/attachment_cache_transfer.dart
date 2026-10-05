part of 'encrypted_attachment_cache.dart';

extension _AttachmentTransferCacheOps on EncryptedAttachmentCache {
  Future<void> prepareRemovalState(
    AttachmentBinding binding,
    Attachment attachment,
  ) => _serialized(() async {
    _require(binding, NoteOperation.attachmentWrite);
    if (attachment.noteId != binding.note.noteId) {
      throw StateError('Invalid removal identity');
    }
    await store.updateIndex((index) {
      _require(binding, NoteOperation.attachmentWrite);
      final record = index[attachment.id];
      if (record is Map &&
          (record['scope'] != _scope(binding) ||
              record['sizeBytes'] != attachment.sizeBytes)) {
        throw StateError('Invalid removal cache');
      }
      if (record is Map &&
          {'remoteCancelling', 'remoteCancelled'}.contains(record['phase'])) {
        return index;
      }
      return {
        ...index,
        attachment.id: {
          'scope': _scope(binding),
          'sizeBytes': attachment.sizeBytes,
          'chunkCount': record is Map ? record['chunkCount'] : 0,
          'phase': 'removing',
        },
      };
    });
  });

  Future<List<String>> removalStateIds(AttachmentBinding binding) async {
    _require(binding, NoteOperation.attachmentWrite);
    final index = await store.readIndex();
    _require(binding, NoteOperation.attachmentWrite);
    return index.entries
        .where(
          (e) =>
              (e.value as Map)['scope'] == _scope(binding) &&
              (e.value as Map)['phase'] == 'removing',
        )
        .map((e) => e.key)
        .toList();
  }

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
        var chunks = 0;
        await store.updateIndex((index) {
          _require(binding, NoteOperation.attachmentWrite);
          final record = index[id];
          if (record is! Map ||
              record['scope'] != _scope(binding) ||
              !{
                'queued',
                'removing',
                'remoteCancelling',
                'remoteCancelled',
              }.contains(record['phase'])) {
            throw StateError('Invalid cancellation.');
          }
          chunks = record['chunkCount'] as int;
          return {
            ...index,
            id: {...record, 'phase': 'remoteCancelling'},
          };
        });
        for (var chunk = 0; chunk < chunks; chunk++) {
          await store.removeChunk(_chunk(id, chunk));
        }
        await store.removeChunk('$id-meta');
        _require(binding, NoteOperation.attachmentWrite);
        await store.updateIndex((index) {
          _require(binding, NoteOperation.attachmentWrite);
          final record = index[id] as Map;
          if (record['scope'] != _scope(binding) ||
              record['phase'] != 'remoteCancelling') {
            throw StateError('Invalid cancellation cleanup');
          }
          return {
            ...index,
            id: {...record, 'phase': 'remoteCancelled'},
          };
        });
      });
  Future<List<String>> cancelStateIds(AttachmentBinding binding) async {
    _require(binding, NoteOperation.attachmentWrite);
    final index = await store.readIndex();
    _require(binding, NoteOperation.attachmentWrite);
    return index.entries
        .where(
          (e) =>
              (e.value as Map)['scope'] == _scope(binding) &&
              {
                'remoteCancelling',
                'remoteCancelled',
              }.contains((e.value as Map)['phase']),
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
            !{'remoteCancelling', 'remoteCancelled'}.contains(entry['phase'])) {
          throw StateError('Invalid cancellation ACK.');
        }
        await _removeStaging(id, entry['chunkCount'] as int);
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
          (n, r) =>
              n +
              ((r as Map)['phase'] == 'remoteCancelled'
                  ? 0
                  : r['sizeBytes'] as int),
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
    final digest = _DigestSink();
    final hasher = crypto.sha256.startChunkedConversion(digest);
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
          await _serialized(() async {
            final index = await store.readIndex();
            _require(binding, NoteOperation.attachmentRead);
            final current = index[id];
            if (current is! Map ||
                current['scope'] != scope ||
                !{'queued', 'linked', 'remote'}.contains(current['phase'])) {
              throw StateError('Attachment cache was removed during read.');
            }
            await store.writeChunk(_chunk(id, i), packet);
          });
        }
        _require(binding, NoteOperation.attachmentRead);
        if (bytes.length != chunkEnd - base) {
          throw StateError('Invalid cached byte range.');
        }
        if (start == 0 && stop == attachment.sizeBytes) hasher.add(bytes);
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
    hasher.close();
    if (start == 0 &&
        stop == attachment.sizeBytes &&
        digest.value.toString() != attachment.sha256) {
      throw const FormatException('Attachment checksum does not match.');
    }
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
