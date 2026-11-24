import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../sync/local_sync_store_account_namespace.dart';
import 'attachment_blob_store.dart';
import 'attachment_store_codec.dart';

AttachmentBlobStore createAttachmentBlobStore({required String actorId}) =>
    FileAttachmentBlobStore(actorId: actorId);

/// One instance per account in composition. Binary files are encrypted packets;
/// no original path/name enters a directory or diagnostic.
final class FileAttachmentBlobStore implements AttachmentBlobStore {
  FileAttachmentBlobStore({
    required String actorId,
    Future<String> Function()? supportPath,
  }) : _namespace = LocalSyncAccountNamespace(actorId),
       _supportPath =
           supportPath ??
           (() async => (await getApplicationSupportDirectory()).path);
  final LocalSyncAccountNamespace _namespace;
  final Future<String> Function() _supportPath;
  Future<void> _tail = Future.value();
  var _sequence = 0;

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final pending = _tail.then((_) => operation());
    _tail = pending.then<void>((_) {}, onError: (Object _) {});
    return pending;
  }

  Future<File> _file(String key) async {
    final base = await _supportPath();
    final directory = Directory(
      '$base${Platform.pathSeparator}accounts${Platform.pathSeparator}${_namespace.hash}${Platform.pathSeparator}attachment_cache',
    );
    await directory.create(recursive: true);
    return File('${directory.path}${Platform.pathSeparator}$key.json');
  }

  Future<String?> _read(String key) async {
    final file = await _file(key);
    if (!await file.exists()) return null;
    if (await file.length() > 1024 * 1024) {
      throw const FormatException('Encrypted cache record exceeds its bound.');
    }
    return file.readAsString();
  }

  Future<void> _write(String key, String json) async {
    final file = await _file(key);
    final temporary = File(
      '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
    );
    try {
      await temporary.writeAsString(json, flush: true);
      await temporary.rename(file.path);
    } on Object {
      if (await temporary.exists()) await temporary.delete();
      throw StateError('Encrypted binary cache could not be saved.');
    }
  }

  @override
  Future<Map<String, Object?>> readIndex() => _serialized(
    () async => AttachmentStoreCodec.index(await _read('index') ?? '{}'),
  );
  @override
  Future<Map<String, Object?>> updateIndex(
    Map<String, Object?> Function(Map<String, Object?>) change,
  ) => _serialized(() async {
    final current = AttachmentStoreCodec.index(await _read('index') ?? '{}');
    final next = AttachmentStoreCodec.index(jsonEncode(change(current)));
    await _write('index', jsonEncode(next));
    return next;
  });
  @override
  Future<Map<String, Object?>?> readChunk(String key) => _serialized(() async {
    final raw = await _read(checkedAttachmentRecordKey(key));
    return raw == null ? null : AttachmentStoreCodec.packet(raw);
  });
  @override
  Future<void> writeChunk(String key, Map<String, Object?> encryptedPacket) =>
      _serialized(() async {
        final json = jsonEncode(encryptedPacket);
        AttachmentStoreCodec.packet(json);
        await _write(checkedAttachmentRecordKey(key), json);
      });
  @override
  Future<void> removeChunk(String key) => _serialized(() async {
    final file = await _file(checkedAttachmentRecordKey(key));
    if (await file.exists()) await file.delete();
  });
}
