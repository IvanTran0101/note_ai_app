import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../application/sync/local_sync_store.dart';
import '../security/encoded_account_store.dart';
import '../security/encrypted_sync_store.dart';
import '../security/paged_account_store.dart';
import 'local_sync_store_account_namespace.dart';
import 'local_sync_store_contract.dart';

part 'local_sync_pages_io.dart';

ILocalSyncStore createLocalSyncStore({
  required String accountUserId,
  LocalSyncApplicationSupportPathResolver? applicationSupportPathResolver,
}) => FileLocalSyncStore(
  accountUserId: accountUserId,
  applicationSupportPathResolver: applicationSupportPathResolver,
);

final class FileLocalSyncStore extends EncryptedSyncStore {
  FileLocalSyncStore({
    required String accountUserId,
    LocalSyncApplicationSupportPathResolver? applicationSupportPathResolver,
  }) : super(
         accountUserId,
         _FileAccountStore(accountUserId, applicationSupportPathResolver),
       );
}

final class _FileAccountStore
    implements EncodedAccountStore, PagedAccountStore {
  _FileAccountStore(String accountId, this.resolver)
    : namespace = LocalSyncAccountNamespace(accountId);
  final LocalSyncAccountNamespace namespace;
  final LocalSyncApplicationSupportPathResolver? resolver;
  static int _sequence = 0;
  static final Map<String, Future<void>> _tails = {};
  bool _stagingCleaned = false;
  @override
  bool pageMode = false;

  Future<File> _file() async {
    try {
      final directory = resolver == null
          ? (await getApplicationSupportDirectory()).path
          : await resolver!();
      if (directory.trim().isEmpty) throw const FormatException();
      final separator = Platform.pathSeparator;
      return File(
        '$directory${separator}accounts$separator${namespace.hash}${separator}local_sync_state.json',
      );
    } on Object {
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.unavailable,
        'local storage unavailable',
      );
    }
  }

  Future<String?> _read(File file) async {
    if (!await file.exists()) return null;
    if (await file.length() > 32 * 1024 * 1024) throw const FormatException();
    return file.readAsString();
  }

  @override
  Future<String?> readEncoded() async {
    try {
      return await _readCanonical(await _file());
    } on Object {
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.unreadable,
        'local state cannot be read',
      );
    }
  }

  @override
  Future<bool> compareAndSet(String? expected, String encrypted) async {
    return _serializedCommit(expected, encrypted, null);
  }

  @override
  Future<bool> compareAndSetPaged(
    String? expected,
    String encrypted,
    PagedEncodedCommit pages,
  ) => _serializedCommit(expected, encrypted, pages);

  Future<bool> _serializedCommit(
    String? expected,
    String encrypted,
    PagedEncodedCommit? pages,
  ) async {
    final previous = _tails[namespace.hash] ?? Future<void>.value();
    final release = Completer<void>();
    _tails[namespace.hash] = release.future;
    await previous;
    try {
      return await _commit(expected, encrypted, pages);
    } finally {
      release.complete();
    }
  }

  Future<bool> _commit(
    String? expected,
    String encrypted,
    PagedEncodedCommit? pages,
  ) async {
    final target = await _file();
    RandomAccessFile? lock;
    File? temporary;
    try {
      await target.parent.create(recursive: true);
      lock = await File('${target.path}.lock').open(mode: FileMode.append);
      await lock.lock(FileLock.blockingExclusive);
      if (await _readCanonical(target) != expected) return false;
      final published = pages != null || pageMode
          ? await _preparePages(target, encrypted, pages)
          : encrypted;
      temporary = File(
        '${target.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}-${++_sequence}',
      );
      await temporary.create(exclusive: true);
      final handle = await temporary.open(mode: FileMode.writeOnly);
      try {
        await handle.writeString(published);
        await handle.flush();
      } finally {
        await handle.close();
      }
      await temporary.rename(target.path);
      if (pages != null || pageMode) {
        pageMode = true;
        await _collectPages(target, published, pages?.liveKeys ?? const {});
      }
      return true;
    } on Object catch (error) {
      if (error is CorruptPageRead) rethrow;
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.unwritable,
        'encrypted state cannot be committed',
      );
    } finally {
      try {
        if (temporary != null && await temporary.exists()) {
          await temporary.delete();
        }
      } on Object {
        /* issued ciphertext only */
      }
      if (lock != null) {
        try {
          await lock.unlock();
        } on Object {
          /* fixed persistence result already returned */
        }
        try {
          await lock.close();
        } on Object {
          /* never expose filesystem errors */
        }
      }
    }
  }

  @override
  Future<PagedEncodedView?> openPagedView() => _openPages();
  @override
  Future<String> readPagedRecord(String generation, String key) =>
      _readPage(generation, key);
  @override
  Future<void> requirePagedGeneration(String generation) =>
      _requirePages(generation);

  @override
  Future<void> cleanLegacyStaging(
    String accountId,
    Future<String> Function(String) sealLegacy,
  ) async {
    if (_stagingCleaned) return;
    final target = await _file();
    if (!await target.parent.exists()) {
      _stagingCleaned = true;
      return;
    }
    try {
      var count = 0;
      await for (final entry in target.parent.list(followLinks: false)) {
        if (entry is! File || !entry.path.startsWith('${target.path}.tmp-')) {
          continue;
        }
        if (++count > 32) throw const FormatException();
        final raw = await _read(entry);
        if (raw == null) continue;
        Object? document;
        try {
          document = jsonDecode(raw);
        } on Object {
          continue;
        }
        if (document is Map &&
            document['schemaVersion'] == 2 &&
            document['accountUserId'] == accountId) {
          await _sealStaging(entry, await sealLegacy(raw));
        }
      }
      _stagingCleaned = true;
    } on Object {
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.unwritable,
        'legacy staging cleanup is incomplete',
      );
    }
  }

  Future<void> _sealStaging(File target, String encrypted) async {
    final issued = File(
      '${target.path}.sealed-${DateTime.now().microsecondsSinceEpoch}-${++_sequence}',
    );
    try {
      await issued.create(exclusive: true);
      final handle = await issued.open(mode: FileMode.writeOnly);
      try {
        await handle.writeString(encrypted);
        await handle.flush();
      } finally {
        await handle.close();
      }
      await issued.rename(target.path);
    } finally {
      try {
        if (await issued.exists()) {
          await issued.delete();
        }
      } on Object {
        /* ciphertext only */
      }
    }
  }
}
