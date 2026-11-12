part of 'encrypted_state_codec.dart';

final class DecryptedPageIndex {
  const DecryptedPageIndex(this.metadata, this.records);
  final LocalSyncState metadata;
  final Map<String, String> records;
}

extension EncryptedPageCodec on EncryptedStateCodec {
  String _pageAad(String suffix) =>
      'NoteFlow/pages/v1/${namespace.hash}/$suffix';
  String _pageIdentity(LocalNoteState n) => page_digest.sha256
      .convert(
        utf8.encode(jsonEncode([namespace.accountUserId, n.ownerId, n.id])),
      )
      .toString();

  LocalNoteState _pageHeader(LocalNoteState n) {
    final readable = !n.protection.enabled && n.contentAvailable;
    return LocalNoteState(
      id: n.id,
      ownerId: n.ownerId,
      title: '',
      content: '',
      createdAt: n.createdAt,
      updatedAt: n.updatedAt,
      pinnedAt: n.pinnedAt,
      serverRevision: n.serverRevision,
      deletedAt: n.deletedAt,
      status: n.status,
      protection: n.protection,
      contentAvailable: readable,
      share: n.share,
      labelIds: readable ? n.labelIds : const [],
      labelProjections: readable ? n.labelProjections : const [],
    );
  }

  void requirePageEpoch(int captured) {
    if (_disposed || generation != captured) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
  }

  Future<String> _pageTag(Map<String, Object?> data) async {
    final bytes = utf8.encode(jsonEncode(data));
    try {
      final mac = await Hmac.sha256().calculateMac(
        bytes,
        secretKey: _deviceKey!,
      );
      return mac.bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<DecryptedPageIndex> openPageIndex(PagedEncodedView view) async {
    final captured = generation;
    requirePageEpoch(captured);
    Map<String, Object?> outer;
    try {
      outer = Map<String, Object?>.from(jsonDecode(view.index) as Map);
      if (outer.length != 3 ||
          outer['schemaVersion'] != 1 ||
          outer['keyId'] is! String ||
          !validPageGeneration(view.generation)) {
        throw const FormatException();
      }
    } on Object {
      throw const CorruptPageRead();
    }
    final id = outer['keyId'] as String;
    if (_keyId != id) {
      final key = await deviceKeys.read(id); // Never regenerate a missing key.
      if (_disposed || generation != captured) {
        key.destroy();
        requirePageEpoch(captured);
      }
      _deviceKey?.destroy();
      _deviceKey = key;
      _keyId = id;
    }
    try {
      final data = await crypto.decryptJson(
        outer['packet'],
        _deviceKey!,
        _pageAad('index/${view.generation}'),
      );
      requirePageEpoch(captured);
      if (data.length != 2) throw const FormatException();
      final metadata = LocalSyncStateCodec.decode(data['state']);
      namespace.requireOwned(metadata);
      final records = Map<String, String>.from(data['records'] as Map);
      var readableCount = 0;
      for (final n in metadata.notes) {
        if (n.title.isNotEmpty ||
            n.content.isNotEmpty ||
            n.document != null ||
            n.attachments.isNotEmpty ||
            n.isDeleted ||
            n.protection.enabled && n.contentAvailable) {
          throw const FormatException();
        }
        final record = records[n.referenceFor(namespace.accountUserId)];
        if (n.contentAvailable && !n.protection.enabled) readableCount++;
        if (n.contentAvailable &&
            !n.protection.enabled &&
            (record == null ||
                !validPageRecordKey(record) ||
                !record.startsWith('${_pageIdentity(n)}-'))) {
          throw const FormatException();
        }
      }
      if (records.length != readableCount ||
          records.values.toSet().length != readableCount ||
          metadata.outbox.isNotEmpty ||
          metadata.conflicts.isNotEmpty) {
        throw const FormatException();
      }
      return DecryptedPageIndex(metadata, Map.unmodifiable(records));
    } on Object {
      requirePageEpoch(captured);
      throw const CorruptPageRead();
    }
  }

  Future<PagedEncodedCommit> encodePageIndex(
    LocalSyncState state, {
    PagedEncodedView? previous,
  }) async {
    final captured = generation;
    await _ensureDeviceKey();
    requirePageEpoch(captured);
    Map<String, String> prior = const {};
    if (previous != null) {
      try {
        final outer = Map<String, Object?>.from(
          jsonDecode(previous.index) as Map,
        );
        if (outer['keyId'] == _keyId) {
          prior = (await openPageIndex(previous)).records;
        }
      } on CorruptPageRead {
        /* Rebuild the derived cache from canonical state. */
      } on FormatException {
        /* Damaged derived envelope: canonical key stays authoritative. */
      } on TypeError {
        /* Damaged derived envelope: canonical key stays authoritative. */
      }
    }
    final records = <String, String>{}, upserts = <String, String>{};
    for (final n in state.notes) {
      if (n.isDeleted || n.protection.enabled || !n.contentAvailable) continue;
      final data = LocalNoteStateCodec.encode(n);
      final key = '${_pageIdentity(n)}-${await _pageTag(data)}';
      final ref = n.referenceFor(namespace.accountUserId);
      records[ref] = key;
      if (prior[ref] != key) {
        upserts[key] = jsonEncode(
          await crypto.encryptJson(data, _deviceKey!, _pageAad('record/$key')),
        );
      }
      requirePageEpoch(captured);
    }
    final metadata = LocalSyncState(
      accountUserId: namespace.accountUserId,
      notes: state.notes.where((n) => !n.isDeleted).map(_pageHeader),
      labels: state.labels,
      syncWireVersion: state.syncWireVersion,
    );
    final g = crypto
        .randomBytes(16)
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join();
    final packet = await crypto.encryptJson(
      {'state': LocalSyncStateCodec.encode(metadata), 'records': records},
      _deviceKey!,
      _pageAad('index/$g'),
    );
    requirePageEpoch(captured);
    return PagedEncodedCommit(
      generation: g,
      index: jsonEncode({
        'schemaVersion': 1,
        'keyId': _keyId,
        'packet': packet,
      }),
      upserts: upserts,
      liveKeys: records.values.toSet(),
    );
  }

  Future<LocalNoteState> openPageNote(
    String raw,
    String key,
    LocalNoteState header,
  ) async {
    final captured = generation;
    requirePageEpoch(captured);
    try {
      final data = await crypto.decryptJson(
        jsonDecode(raw),
        _deviceKey!,
        _pageAad('record/$key'),
      );
      if (key != '${_pageIdentity(header)}-${await _pageTag(data)}') {
        throw const FormatException();
      }
      final note = LocalNoteStateCodec.decode(data);
      if (jsonEncode(LocalNoteStateCodec.encode(_pageHeader(note))) !=
          jsonEncode(LocalNoteStateCodec.encode(header))) {
        throw const FormatException();
      }
      requirePageEpoch(captured);
      return note;
    } on Object {
      requirePageEpoch(captured);
      throw const CorruptPageRead();
    }
  }
}
