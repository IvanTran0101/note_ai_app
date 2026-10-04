import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:indexed_db/indexed_db.dart';

import '../sync/local_sync_store_account_namespace.dart';
import 'attachment_blob_store.dart';
import 'attachment_store_codec.dart';

AttachmentBlobStore createAttachmentBlobStore({required String actorId}) =>
    IndexedDbAttachmentBlobStore(actorId: actorId);

/// Ciphertext chunks live separately from the small Note sync document. Each
/// quota reservation commits in an IndexedDB transaction, including across tabs.
final class IndexedDbAttachmentBlobStore implements AttachmentBlobStore {
  IndexedDbAttachmentBlobStore({required String actorId})
    : _namespace = LocalSyncAccountNamespace(actorId);
  final LocalSyncAccountNamespace _namespace;
  Future<Database>? _opening;
  static const _records = 'encrypted_chunks';

  Future<Database> _database() {
    final opening = _opening;
    if (opening != null) return opening;
    final pending = IdbFactory().open(
      'note_ai_app_binary_${_namespace.hash}',
      version: 1,
      onUpgradeNeeded: (event) {
        event.target.database.createObjectStore(_records);
      },
    );
    _opening = pending;
    pending.then<void>(
      (db) {
        db.onVersionChange.listen((_) {
          db.close();
          _opening = null;
        });
      },
      onError: (Object _) {
        _opening = null;
      },
    );
    return pending;
  }

  String _text(Object value) {
    if (value is String) return value;
    if (value.isA<JSString>()) return (value as JSString).toDart;
    throw const FormatException('Encrypted cache record is not text.');
  }

  void _abort(Transaction transaction) {
    transaction.abort();
    unawaited(transaction.completed.then<void>((_) {}, onError: (Object _) {}));
  }

  Future<String?> _read(String key) async {
    final db = await _database();
    final transaction = db.transaction(_records, 'readonly');
    final value = await transaction.objectStore(_records).getObject(key.toJS);
    await transaction.completed;
    return value == null ? null : _text(value);
  }

  @override
  Future<Map<String, Object?>> readIndex() async =>
      AttachmentStoreCodec.index(await _read('index') ?? '{}');
  @override
  Future<Map<String, Object?>> updateIndex(
    Map<String, Object?> Function(Map<String, Object?>) change,
  ) async {
    final db = await _database();
    final transaction = db.transaction(_records, 'readwrite');
    try {
      final store = transaction.objectStore(_records);
      final value = await store.getObject('index'.toJS);
      final current = AttachmentStoreCodec.index(
        value == null ? '{}' : _text(value),
      );
      final next = AttachmentStoreCodec.index(jsonEncode(change(current)));
      await store.put(jsonEncode(next).toJS, 'index'.toJS);
      await transaction.completed;
      return next;
    } on Object {
      _abort(transaction);
      rethrow;
    }
  }

  @override
  Future<Map<String, Object?>?> readChunk(String key) async {
    final raw = await _read(checkedAttachmentRecordKey(key));
    return raw == null ? null : AttachmentStoreCodec.packet(raw);
  }

  @override
  Future<void> writeChunk(
    String key,
    Map<String, Object?> encryptedPacket,
  ) async {
    final text = jsonEncode(encryptedPacket);
    AttachmentStoreCodec.packet(text);
    final db = await _database();
    final transaction = db.transaction(_records, 'readwrite');
    try {
      await transaction
          .objectStore(_records)
          .put(text.toJS, checkedAttachmentRecordKey(key).toJS);
      await transaction.completed;
    } on Object {
      _abort(transaction);
      rethrow;
    }
  }

  @override
  Future<void> removeChunk(String key) async {
    final db = await _database();
    final transaction = db.transaction(_records, 'readwrite');
    try {
      await transaction
          .objectStore(_records)
          .delete(checkedAttachmentRecordKey(key).toJS);
      await transaction.completed;
    } on Object {
      _abort(transaction);
      rethrow;
    }
  }
}
