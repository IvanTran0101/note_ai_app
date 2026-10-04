import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../../application/attachments/attachment_binding.dart';
import '../../application/attachments/attachment_draft_store.dart';
import '../../application/attachments/attachment_input.dart';
import '../../application/attachments/attachment_policy.dart';
import '../../application/attachments/local_attachment_draft.dart';
import '../../domain/notes/attachment.dart';
import '../../domain/notes/note_protection.dart';
import 'attachment_blob_store.dart';
import 'attachment_byte_validation.dart';
import 'attachment_chunk_cipher.dart';

/// Durable staging is encrypted before any transport is allowed to run.
final class EncryptedAttachmentCache implements AttachmentDraftStore {
  EncryptedAttachmentCache({
    required this.actorId,
    required this.store,
    required this.cipher,
    required this.generateId,
  });
  final String actorId;
  final AttachmentBlobStore store;
  final AttachmentChunkCipher cipher;
  final String Function() generateId;
  Future<void> _tail = Future.value();

  // One cache instance per account. Keep stage/link/cancel serialized so a
  // cancelled staging operation cannot recreate chunks after cleanup.
  Future<T> _serialized<T>(Future<T> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  void _require(AttachmentBinding binding, NoteOperation operation) {
    if (binding.actorId != actorId) {
      throw StateError('Binary cache belongs to another account.');
    }
    cipher.requireAccess(binding, operation);
  }

  String _scope(AttachmentBinding binding) => crypto.sha256
      .convert(
        utf8.encode(
          jsonEncode([actorId, binding.note.ownerId, binding.note.noteId]),
        ),
      )
      .toString();
  String _chunk(String id, int index) =>
      checkedAttachmentRecordKey('$id-${index.toString().padLeft(3, '0')}');

  @override
  Future<LocalAttachmentDraft> stage(
    AttachmentBinding binding,
    AttachmentInput input, {
    required Iterable<Attachment> existing,
  }) => _serialized(() => _stage(binding, input, existing: existing));

  Future<LocalAttachmentDraft> _stage(
    AttachmentBinding binding,
    AttachmentInput input, {
    required Iterable<Attachment> existing,
  }) async {
    _require(binding, NoteOperation.attachmentWrite);
    final saved = List<Attachment>.of(existing);
    final mime = AttachmentPolicy.validate(
      fileName: input.fileName,
      mimeType: input.mimeType,
      sizeBytes: input.sizeBytes,
      existing: saved,
    );
    final id = crypto.sha256.convert(utf8.encode(generateId())).toString();
    final scope = _scope(binding);
    await store.updateIndex((index) {
      _require(binding, NoteOperation.attachmentWrite);
      if (index.containsKey(id)) {
        throw StateError('Binary staging identity collision.');
      }
      var used = 0, noteBytes = 0, noteCount = 0;
      for (final raw in index.values) {
        final entry = Map<String, Object?>.from(raw as Map);
        used += entry['sizeBytes'] as int;
        if (entry['scope'] == scope && entry['phase'] != 'linked') {
          noteBytes += entry['sizeBytes'] as int;
          noteCount++;
        }
      }
      if (used + input.sizeBytes > AttachmentPolicy.maxCacheBytes) {
        throw StateError('Encrypted cache quota exceeded.');
      }
      AttachmentPolicy.validate(
        fileName: input.fileName,
        mimeType: mime,
        sizeBytes: input.sizeBytes,
        existing: saved,
        reservedCount: noteCount,
        reservedBytes: noteBytes,
      );
      return {
        ...index,
        id: {
          'scope': scope,
          'sizeBytes': input.sizeBytes,
          'chunkCount': 0,
          'phase': 'staging',
        },
      };
    });
    var count = 0, total = 0;
    var durable = false;
    final buffer = Uint8List(AttachmentPolicy.chunkBytes);
    var filled = 0;
    final digest = _DigestSink();
    final hasher = crypto.sha256.startChunkedConversion(digest);
    Future<void> flush() async {
      if (filled == 0) return;
      final packet = await cipher.seal(
        binding,
        id,
        count,
        Uint8List.sublistView(buffer, 0, filled),
      );
      _require(binding, NoteOperation.attachmentWrite);
      await store.writeChunk(_chunk(id, count), packet);
      _require(binding, NoteOperation.attachmentWrite);
      count++;
      filled = 0;
      buffer.fillRange(0, buffer.length, 0);
    }

    try {
      _require(binding, NoteOperation.attachmentWrite);
      await for (final bytes in input.openRead()) {
        _require(binding, NoteOperation.attachmentWrite);
        total += bytes.length;
        if (total > input.sizeBytes) {
          throw const FormatException('Selected file changed size.');
        }
        hasher.add(bytes);
        var offset = 0;
        while (offset < bytes.length) {
          final available = buffer.length - filled;
          final take = bytes.length - offset < available
              ? bytes.length - offset
              : available;
          buffer.setRange(filled, filled + take, bytes, offset);
          filled += take;
          offset += take;
          if (filled == buffer.length) await flush();
        }
      }
      if (total != input.sizeBytes) {
        throw const FormatException('Selected file was truncated.');
      }
      await flush();
      hasher.close();
      final draft = LocalAttachmentDraft(
        cacheId: id,
        fileName: input.fileName,
        mimeType: mime,
        sizeBytes: total,
        sha256: digest.value!.toString(),
        chunkCount: count,
      );
      // Validate the exact staged bytes, not a second read of a mutable source.
      final staged = AttachmentInput(
        fileName: input.fileName,
        mimeType: mime,
        sizeBytes: total,
        openRead: ([start, end]) => _readChunks(
          binding,
          draft,
          start ?? 0,
          end ?? total,
          operation: NoteOperation.attachmentWrite,
        ),
      );
      await AttachmentByteValidation.validate(staged);
      final metadata = utf8.encode(
        jsonEncode({
          'fileName': draft.fileName,
          'mimeType': mime,
          'sizeBytes': total,
          'sha256': draft.sha256,
          'chunkCount': count,
        }),
      );
      try {
        final packet = await cipher.seal(binding, id, -1, metadata);
        await store.writeChunk('$id-meta', packet);
        _require(binding, NoteOperation.attachmentWrite);
      } finally {
        metadata.fillRange(0, metadata.length, 0);
      }
      await store.updateIndex((index) {
        _require(binding, NoteOperation.attachmentWrite);
        final entry = Map<String, Object?>.from(index[id] as Map);
        return {
          ...index,
          id: {...entry, 'phase': 'queued', 'chunkCount': count},
        };
      });
      durable = true;
      _require(binding, NoteOperation.attachmentWrite);
      return draft;
    } on Object {
      // Never release quota before deleting the ciphertext. Failed cleanup
      // remains reserved and can be retried; no pending plaintext is persisted.
      if (!durable) {
        // Persist an unreadable cleanup marker first. If deletion fails, a
        // later cancellation can retry without advertising a partial file.
        await _markCancelling(id, scope);
        await _removeStaging(id, 200);
      }
      rethrow;
    } finally {
      buffer.fillRange(0, buffer.length, 0);
      if (digest.value == null) hasher.close();
    }
  }

  @override
  Stream<List<int>> read(
    AttachmentBinding binding,
    LocalAttachmentDraft draft, {
    int start = 0,
    int? end,
  }) => _readChunks(binding, draft, start, end ?? draft.sizeBytes);

  @override
  Future<LocalAttachmentDraft> load(
    AttachmentBinding binding,
    String id,
  ) async {
    _require(binding, NoteOperation.attachmentRead);
    checkedAttachmentRecordKey('$id-meta');
    final index = await store.readIndex();
    _require(binding, NoteOperation.attachmentRead);
    final record = index[id];
    if (record is! Map ||
        record['scope'] != _scope(binding) ||
        !{'queued', 'linked'}.contains(record['phase'])) {
      throw StateError('A complete authorized attachment draft is required.');
    }
    final packet = await store.readChunk('$id-meta');
    _require(binding, NoteOperation.attachmentRead);
    if (packet == null) {
      throw StateError('Encrypted attachment metadata is missing.');
    }
    final bytes = await cipher.open(binding, id, -1, packet);
    try {
      final metadata = Map<String, Object?>.from(
        jsonDecode(utf8.decode(bytes)) as Map,
      );
      final fileName = metadata['fileName'] as String;
      final mimeType = metadata['mimeType'] as String;
      final sizeBytes = metadata['sizeBytes'] as int;
      final chunkCount = metadata['chunkCount'] as int;
      final checksum = metadata['sha256'] as String;
      if (metadata.length != 5 ||
          sizeBytes != record['sizeBytes'] ||
          chunkCount != record['chunkCount'] ||
          chunkCount !=
              (sizeBytes + AttachmentPolicy.chunkBytes - 1) ~/
                  AttachmentPolicy.chunkBytes ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum)) {
        throw const FormatException('Invalid encrypted draft metadata.');
      }
      AttachmentPolicy.validate(
        fileName: fileName,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        existing: const [],
      );
      _require(binding, NoteOperation.attachmentRead);
      return LocalAttachmentDraft(
        cacheId: id,
        fileName: fileName,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        sha256: checksum,
        chunkCount: chunkCount,
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  @override
  Future<List<String>> pendingIds(AttachmentBinding binding) async {
    _require(binding, NoteOperation.attachmentRead);
    final index = await store.readIndex();
    _require(binding, NoteOperation.attachmentRead);
    final scope = _scope(binding);
    return List.unmodifiable(
      index.entries
          .where((entry) {
            final record = entry.value as Map;
            return record['scope'] == scope && record['phase'] == 'queued';
          })
          .map((entry) => entry.key),
    );
  }

  @override
  Future<void> markLinked(AttachmentBinding binding, String id) =>
      _serialized(() async {
        _require(binding, NoteOperation.attachmentWrite);
        checkedAttachmentRecordKey('$id-meta');
        await store.updateIndex((index) {
          _require(binding, NoteOperation.attachmentWrite);
          final record = index[id];
          if (record is! Map ||
              record['scope'] != _scope(binding) ||
              !{'queued', 'linked'}.contains(record['phase'])) {
            throw StateError('A complete local attachment is required.');
          }
          return {
            ...index,
            id: {...record, 'phase': 'linked'},
          };
        });
        _require(binding, NoteOperation.attachmentWrite);
      });

  @override
  Future<void> recoverIncomplete(AttachmentBinding binding) =>
      _serialized(() async {
        _require(binding, NoteOperation.attachmentWrite);
        final index = await store.readIndex();
        _require(binding, NoteOperation.attachmentWrite);
        for (final entry in index.entries) {
          final record = entry.value as Map;
          if (record['scope'] != _scope(binding) ||
              !{'staging', 'cancelling'}.contains(record['phase'])) {
            continue;
          }
          _require(binding, NoteOperation.attachmentWrite);
          await _markCancelling(entry.key, _scope(binding), binding: binding);
          await _removeStaging(entry.key, 200);
          _require(binding, NoteOperation.attachmentWrite);
        }
      });

  @override
  Future<void> cancelLocal(AttachmentBinding binding, String id) =>
      _serialized(() => _cancelLocal(binding, id));

  Future<void> _cancelLocal(AttachmentBinding binding, String id) async {
    _require(binding, NoteOperation.attachmentWrite);
    checkedAttachmentRecordKey('$id-meta');
    final index = await store.readIndex();
    _require(binding, NoteOperation.attachmentWrite);
    final record = index[id];
    if (record == null) return;
    if (record is! Map ||
        record['scope'] != _scope(binding) ||
        record['phase'] == 'linked') {
      throw StateError('Only an unlinked local attachment can be cancelled.');
    }
    await _markCancelling(id, _scope(binding), binding: binding);
    // Bound cleanup to one validated draft, including partial staging writes.
    // The durable marker prevents reads if a chunk deletion fails midway.
    await _removeStaging(id, 200);
  }

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

final class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest data) {
    value = data;
  }

  @override
  void close() {}
}
