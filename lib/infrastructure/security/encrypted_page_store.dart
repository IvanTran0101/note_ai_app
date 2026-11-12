part of 'encrypted_sync_store.dart';

extension EncryptedPageStore on EncryptedSyncStore {
  Future<T> _withPageView<T>(Future<T> Function(LocalNotePageView) query) =>
      _enqueue(() async {
        final operationEpoch = codec.generation;
        final disk = backing;
        if (disk is! PagedAccountStore) {
          final state = await _read();
          return query(_MemoryPageView(state));
        }
        final paged = disk as PagedAccountStore;
        for (var attempt = 0; attempt < 5; attempt++) {
          codec.requirePageEpoch(operationEpoch);
          try {
            var snapshot = await paged.openPagedView();
            if (snapshot == null) {
              await _rebuildPageIndex(paged);
              snapshot = await paged.openPagedView();
            }
            if (snapshot == null) throw const StalePageRead();
            final captured = codec.generation;
            final index = await codec.openPageIndex(snapshot);
            codec.requirePageEpoch(operationEpoch);
            final view = _EncryptedPageView(
              this,
              paged,
              snapshot,
              index,
              captured,
            );
            final result = await query(view);
            await view.requireCurrent();
            return result;
          } on StalePageRead {
            continue;
          } on CorruptPageRead {
            await _rebuildPageIndex(paged); // Trusted canonical repair only.
          }
        }
        throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
      });

  Future<void> _rebuildPageIndex(PagedAccountStore disk) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final expected = await backing.readEncoded();
      final state = await codec.decode(expected);
      final encrypted = codec.migrationRequired || expected == null
          ? await codec.encode(state)
          : expected;
      final pages = await codec.encodePageIndex(state); // Re-seal all records.
      if (await disk.compareAndSetPaged(expected, encrypted, pages)) {
        await backing.cleanLegacyStaging(
          codec.namespace.accountUserId,
          codec.sealLegacyStaging,
        );
        return;
      }
    }
    throw const StalePageRead();
  }

  Future<bool> _commitPageAware(
    String? expected,
    String encrypted,
    LocalSyncState state,
  ) async {
    final disk = backing;
    if (disk is! PagedAccountStore || !(disk as PagedAccountStore).pageMode) {
      return backing.compareAndSet(expected, encrypted);
    }
    final paged = disk as PagedAccountStore;
    final captured = codec.generation;
    PagedEncodedView? prior;
    try {
      prior = await paged.openPagedView();
    } on CorruptPageRead {
      /* Re-seal derived cache from the validated state. */
    } on StalePageRead {
      return false;
    }
    codec.requirePageEpoch(captured);
    final pages = await codec.encodePageIndex(state, previous: prior);
    if (captured != codec.generation) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
    try {
      return await paged.compareAndSetPaged(expected, encrypted, pages);
    } on CorruptPageRead {
      // A reused record disappeared after the index was opened. Recover the
      // derived records without dropping the pending canonical transaction.
      codec.requirePageEpoch(captured);
      final repaired = await codec.encodePageIndex(state);
      return paged.compareAndSetPaged(expected, encrypted, repaired);
    }
  }
}

final class _EncryptedPageView implements LocalNotePageView {
  _EncryptedPageView(
    this.store,
    this.disk,
    this.snapshot,
    this.index,
    this.epoch,
  );
  final EncryptedSyncStore store;
  final PagedAccountStore disk;
  final PagedEncodedView snapshot;
  final DecryptedPageIndex index;
  final int epoch;
  @override
  String get accountId => index.metadata.accountUserId;
  @override
  List<LocalNoteState> get headers => index.metadata.notes;
  @override
  List<LocalLabelState> get labels => index.metadata.labels;
  @override
  Future<void> requireCurrent() async {
    store.codec.requirePageEpoch(epoch);
    await disk.requirePagedGeneration(snapshot.generation);
    store.codec.requirePageEpoch(epoch);
  }

  @override
  Future<LocalNoteState> readNote(LocalNoteState header) async {
    store.codec.requirePageEpoch(epoch);
    if (!headers.contains(header)) throw const CorruptPageRead();
    if (!header.contentAvailable || header.protection.enabled) return header;
    final key = index.records[header.referenceFor(accountId)];
    if (key == null) throw const CorruptPageRead();
    final raw = await disk.readPagedRecord(snapshot.generation, key);
    store.codec.requirePageEpoch(epoch);
    store.pagePayloadReads++;
    final note = await store.codec.openPageNote(raw, key, header);
    store.codec.requirePageEpoch(epoch);
    return note;
  }
}

final class _MemoryPageView implements LocalNotePageView {
  const _MemoryPageView(this.state);
  final LocalSyncState state;
  @override
  String get accountId => state.accountUserId;
  @override
  List<LocalNoteState> get headers => state.notes;
  @override
  List<LocalLabelState> get labels => state.labels;
  @override
  Future<LocalNoteState> readNote(LocalNoteState header) async => header;
  @override
  Future<void> requireCurrent() async {}
}
