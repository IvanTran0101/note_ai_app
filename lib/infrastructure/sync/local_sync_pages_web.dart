part of 'local_sync_store_web.dart';

extension _WebPages on _WebAccountStore {
  Future<PagedEncodedView?> _openPages() async {
    final tx = (await _database()).transactionList([
      _WebAccountStore._meta,
    ], 'readonly');
    final meta = tx.objectStore(_WebAccountStore._meta);
    final generation = _WebAccountStore._text(
      await meta.getObject('head'.toJS),
    );
    final index = _WebAccountStore._text(await meta.getObject('index'.toJS));
    await tx.completed;
    pageMode = generation != null;
    if (generation == null || index == null) return null;
    if (!validPageGeneration(generation)) throw const CorruptPageRead();
    return PagedEncodedView(generation, index);
  }

  Future<String> _readPage(String generation, String key) async {
    if (!validPageGeneration(generation) || !validPageRecordKey(key)) {
      throw const CorruptPageRead();
    }
    final tx = (await _database()).transactionList([
      _WebAccountStore._meta,
      _WebAccountStore._pages,
    ], 'readonly');
    final head = _WebAccountStore._text(
      await tx.objectStore(_WebAccountStore._meta).getObject('head'.toJS),
    );
    final raw = _WebAccountStore._text(
      await tx.objectStore(_WebAccountStore._pages).getObject(key.toJS),
    );
    await tx.completed;
    if (head != generation) throw const StalePageRead();
    if (raw == null) throw const CorruptPageRead();
    return raw;
  }

  Future<void> _requirePages(String generation) async {
    final tx = (await _database()).transactionList([
      _WebAccountStore._meta,
    ], 'readonly');
    final head = _WebAccountStore._text(
      await tx.objectStore(_WebAccountStore._meta).getObject('head'.toJS),
    );
    await tx.completed;
    if (head != generation) throw const StalePageRead();
  }

  Future<bool> _commitPages(
    String? expected,
    String encrypted,
    PagedEncodedCommit? pages,
  ) async {
    if (pages != null &&
        (!validPageGeneration(pages.generation) ||
            !pages.liveKeys.every(validPageRecordKey) ||
            !pages.upserts.keys.every(pages.liveKeys.contains))) {
      throw const CorruptPageRead();
    }
    Transaction? tx;
    Future<Database>? committed;
    try {
      tx = (await _database()).transactionList([
        _WebAccountStore._store,
        _WebAccountStore._meta,
        _WebAccountStore._pages,
      ], 'readwrite');
      committed = tx.completed;
      // Observe aborts immediately, including failures before the final await.
      unawaited(
        committed.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      final canonical = tx.objectStore(_WebAccountStore._store);
      final meta = tx.objectStore(_WebAccountStore._meta);
      final records = tx.objectStore(_WebAccountStore._pages);
      final current = _WebAccountStore._text(
        await canonical.getObject(_WebAccountStore._record.toJS),
      );
      if (current != expected) {
        await committed;
        return false;
      }
      final previous = _WebAccountStore._text(
        await meta.getObject('head'.toJS),
      );
      if (pages == null) {
        await records.clear();
        await meta.delete('index'.toJS);
        if (previous != null) {
          await meta.put(newPageGeneration().toJS, 'head'.toJS);
        }
      } else {
        // Only enumerate keys: never deserialize unrelated note bodies.
        final request = records.getAllKeys(null);
        await Future.any([
          request.onSuccess.first,
          committed.then((_) => throw const CorruptPageRead()),
        ]);
        final keys = (request.result as JSArray).toDart;
        final present = keys.map(_WebAccountStore._text).toSet();
        if (!pages.liveKeys
            .difference(pages.upserts.keys.toSet())
            .every(present.contains)) {
          throw const CorruptPageRead();
        }
        for (final key in keys) {
          final text = _WebAccountStore._text(key);
          if (!pages.liveKeys.contains(text)) await records.delete(key);
        }
        for (final entry in pages.upserts.entries) {
          await records.put(entry.value.toJS, entry.key.toJS);
        }
        await meta.put(pages.generation.toJS, 'head'.toJS);
        await meta.put(pages.index.toJS, 'index'.toJS);
      }
      await canonical.put(encrypted.toJS, _WebAccountStore._record.toJS);
      await committed;
      pageMode = pages != null || previous != null;
      return true;
    } on Object catch (error) {
      try {
        tx?.abort();
      } on Object {
        /* Already complete. */
      }
      if (error is CorruptPageRead) rethrow;
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.unwritable,
        'encrypted page state cannot be committed',
      );
    }
  }
}
