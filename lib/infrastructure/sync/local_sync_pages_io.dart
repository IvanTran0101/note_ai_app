part of 'local_sync_store_io.dart';

/// A flushed manifest rename is the only publication point. The original lock
/// and CAS are shared with pre-pagination writers; schema4 fences their reads.
extension _FilePages on _FileAccountStore {
  Map<String, Object?>? _manifest(String? raw) {
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['schemaVersion'] != 4) return null;
    final map = Map<String, Object?>.from(decoded);
    if (map.length != 4 ||
        map['format'] != 'NoteFlow/pages/v1' ||
        map['generation'] is! String ||
        !validPageGeneration(map['generation'] as String) ||
        map['hasIndex'] is! bool) {
      throw const CorruptPageRead();
    }
    return map;
  }

  Directory _pageDirectory(File root) =>
      Directory('${root.parent.path}${Platform.pathSeparator}note_pages_v1');
  File _pageFile(File root, String name) =>
      File('${_pageDirectory(root).path}${Platform.pathSeparator}$name');

  Future<String?> _readCanonical(File root) async {
    for (var retry = 0; retry < 5; retry++) {
      final raw = await _read(root);
      if (raw == null &&
          await _pageDirectory(root).exists() &&
          !await _pageDirectory(root).list(followLinks: false).isEmpty) {
        // Missing commit pointer is damaged storage, never a new empty account.
        throw const CorruptPageRead();
      }
      final manifest = _manifest(raw);
      if (manifest == null) return raw;
      pageMode = true;
      try {
        final result = await _read(
          _pageFile(root, '${manifest['generation']}.state'),
        );
        if (result != null) return result;
      } on FileSystemException {
        if (raw == await _read(root)) rethrow;
        continue;
      }
      if (raw == await _read(root)) throw const CorruptPageRead();
    }
    throw const StalePageRead();
  }

  Future<PagedEncodedView?> _openPages() async {
    final root = await _file();
    final manifest = _manifest(await _read(root));
    if (manifest == null) return null;
    pageMode = true;
    if (manifest['hasIndex'] != true) return null;
    final generation = manifest['generation'] as String;
    String? index;
    try {
      index = await _read(_pageFile(root, '$generation.index'));
    } on FileSystemException {
      await _requirePages(generation);
      throw const CorruptPageRead();
    }
    await _requirePages(generation);
    if (index == null) throw const CorruptPageRead();
    return PagedEncodedView(generation, index);
  }

  Future<void> _requirePages(String generation) async {
    final manifest = _manifest(await _read(await _file()));
    if (manifest?['generation'] != generation) throw const StalePageRead();
  }

  Future<String> _readPage(String generation, String key) async {
    if (!validPageGeneration(generation) || !validPageRecordKey(key)) {
      throw const CorruptPageRead();
    }
    await _requirePages(generation);
    final root = await _file();
    String? raw;
    try {
      raw = await _read(_pageFile(root, '$key.record'));
    } on FileSystemException {
      await _requirePages(generation);
      throw const CorruptPageRead();
    }
    await _requirePages(generation);
    if (raw == null) throw const CorruptPageRead();
    return raw;
  }

  Future<void> _flushPage(File file, String raw) async {
    // Per-record names are content-addressed. Re-sealing a damaged derived
    // record must use rename so a concurrent old-generation reader is atomic.
    final staged = File(
      '${file.path}.pending-$pid-${++_FileAccountStore._sequence}',
    );
    try {
      final handle = await staged.open(mode: FileMode.writeOnly);
      try {
        await handle.writeString(raw);
        await handle.flush();
      } finally {
        await handle.close();
      }
      await staged.rename(file.path);
    } finally {
      try {
        if (await staged.exists()) await staged.delete();
      } on Object {
        /* Ciphertext only. */
      }
    }
  }

  Future<String> _preparePages(
    File root,
    String canonical,
    PagedEncodedCommit? pages,
  ) async {
    if (pages != null &&
        (!validPageGeneration(pages.generation) ||
            !pages.liveKeys.every(validPageRecordKey) ||
            !pages.upserts.keys.every(pages.liveKeys.contains))) {
      throw const CorruptPageRead();
    }
    final generation = pages?.generation ?? newPageGeneration();
    await _pageDirectory(root).create(recursive: true);
    if (pages != null) {
      for (final entry in pages.upserts.entries) {
        await _flushPage(_pageFile(root, '${entry.key}.record'), entry.value);
      }
      // A missing reused record must never be acknowledged as a valid commit.
      for (final key in pages.liveKeys.difference(pages.upserts.keys.toSet())) {
        if (!await _pageFile(root, '$key.record').exists()) {
          throw const CorruptPageRead();
        }
      }
      await _flushPage(_pageFile(root, '$generation.index'), pages.index);
    }
    await _flushPage(_pageFile(root, '$generation.state'), canonical);
    return jsonEncode({
      'schemaVersion': 4,
      'format': 'NoteFlow/pages/v1',
      'generation': generation,
      'hasIndex': pages != null,
    });
  }

  Future<void> _collectPages(
    File root,
    String published,
    Set<String> liveKeys,
  ) async {
    // Best effort after ACK point. Never report a failed write after commit.
    try {
      final generation = _manifest(published)!['generation'];
      await for (final entry in _pageDirectory(root).list(followLinks: false)) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        final record = name.endsWith('.record')
            ? name.substring(0, name.length - 7)
            : '';
        final ownedGeneration = RegExp(r'^[a-f0-9]{32}\.(state|index)$')
            .hasMatch(name);
        if (validPageRecordKey(record) && !liveKeys.contains(record) ||
            ownedGeneration &&
                name != '$generation.state' &&
                name != '$generation.index') {
          await entry.delete();
        }
      }
    } on Object {
      /* A later commit retries ciphertext-only garbage collection. */
    }
  }
}
