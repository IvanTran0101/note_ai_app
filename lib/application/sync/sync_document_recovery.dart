part of 'sync_state_reconciliation.dart';

/// Recovery uses the same canonical reconciliation transaction.
extension SyncDocumentRecovery on SyncStateReconciliation {
  /// Capability recovery retries the exact immutable attempted payload/id.
  /// Permission errors and conflicts retain their separate recovery paths.
  Future<LocalSyncState> retryDocumentUpgrade() => update((current) {
    final recovered = <String>{};
    final entries = current.outbox.map((entry) {
      if (!entry.blocked ||
          entry.lastError != SyncErrorCode.documentRequiresUpgrade ||
          entry.payload?.includesDocument != true ||
          current.conflicts.any(
            (c) => c.pending.mutationId == entry.mutationId,
          )) {
        return entry;
      }
      recovered.add(entry.keyFor(accountUserId));
      return copyEntry(entry, blocked: false);
    }).toList();
    if (recovered.isEmpty) return current;
    return copyState(
      current,
      outbox: entries,
      notes: current.notes.map(
        (note) => recovered.contains(note.identity.key) && note.contentAvailable
            ? withStatus(note, NoteSyncStatus.pending)
            : note,
      ),
    );
  });
}
