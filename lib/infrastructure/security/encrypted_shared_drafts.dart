part of 'encrypted_state_codec.dart';

/// Access changes keep draft evidence encrypted and stop stale epoch replay.
extension EncryptedSharedDrafts on EncryptedStateCodec {
  Future<void> retainEditorEvidence(
    NoteDto selected,
    String title,
    String content, {
    NoteDocument? document,
  }) async {
    if (selected.share?.recipientId != namespace.accountUserId ||
        selected.ownerId == namespace.accountUserId ||
        !selected.contentAvailable) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
    }
    if (document != null && content != document.plainText) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.invalidInput);
    }
    final evidence = <String, Object?>{
      'ownerId': selected.ownerId,
      'noteId': selected.id,
      'contentRevision': selected.contentRevision,
      'title': title,
      'content': content,
      if (document != null) 'document': NoteDocumentCodec.encode(document),
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
    };
    if (document != null && utf8.encode(jsonEncode(evidence)).length > 300000) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
    }
    await _ensureDeviceKey();
    final reference = selected.identity.referenceFor(namespace.accountUserId);
    _retained[reference] = [
      ...((_retained[reference] as List?) ?? []),
      {
        'kind': 'editorDraft',
        'accessRevision': selected.share!.accessRevision,
        'box': await crypto.encryptJson(
          evidence,
          _deviceKey!,
          '$_accountAad/shared-editor/${jsonEncode(reference)}',
        ),
      },
    ];
  }

  Future<LocalSyncState> retainAccessChanges(
    LocalSyncState previous,
    LocalSyncState next,
  ) async {
    Map<String, Object?>? projected;
    for (final old in previous.notes) {
      if (old.ownerId == namespace.accountUserId) continue;
      final current = next.notes
          .where((n) => n.identity == old.identity)
          .firstOrNull;
      if (current?.share == old.share &&
          current?.protection == old.protection) {
        continue;
      }
      final reference = old.referenceFor(namespace.accountUserId);
      final losesEpoch =
          current?.share?.accessRevision != old.share?.accessRevision;
      final losesWrite =
          losesEpoch ||
          current?.share?.isActive != true ||
          current?.share?.role != NoteRole.editor ||
          current?.protection != old.protection;
      if (losesWrite &&
          previous.outbox.any(
            (m) =>
                !m.isLabel &&
                m.mutation.identityFor(namespace.accountUserId) == old.identity,
          )) {
        await _retainSharedDraft(previous, old, reference);
        projected ??= LocalSyncStateCodec.encode(next);
        NoteBundleProjection.redactWork(projected, reference);
        _markAccessBlocked(projected, reference);
      }
      if (losesEpoch ||
          current?.share?.isActive != true ||
          current?.protection != old.protection) {
        _parkSharedKey(reference);
        if (current != null &&
            (current.share?.isActive != true || current.protection.enabled)) {
          projected ??= LocalSyncStateCodec.encode(next);
          NoteBundleProjection.redact(projected, reference);
        }
      }
    }
    return projected == null ? next : LocalSyncStateCodec.decode(projected);
  }

  Future<void> _retainSharedDraft(
    LocalSyncState previous,
    LocalNoteState note,
    String reference,
  ) async {
    await _ensureDeviceKey();
    final pendingIds = previous.outbox
        .where(
          (m) =>
              !m.isLabel &&
              m.mutation.identityFor(namespace.accountUserId) == note.identity,
        )
        .map((m) => m.mutationId)
        .toList();
    _retained[reference] = [
      ...((_retained[reference] as List?) ?? []),
      {
        'kind': 'sharedDraft',
        'accessRevision': note.share?.accessRevision,
        'pendingIds': pendingIds,
        'box': await crypto.encryptJson(
          NoteBundleProjection.bundle(
            LocalSyncStateCodec.encode(previous),
            reference,
          ),
          _deviceKey!,
          '$_accountAad/shared-draft/${jsonEncode(reference)}',
        ),
      },
    ];
  }

  void _parkSharedKey(String reference) {
    final record = _records.remove(reference);
    if (record != null) {
      _retained[reference] = [
        ...((_retained[reference] as List?) ?? []),
        record,
      ];
    }
    lock(reference);
  }

  void _markAccessBlocked(Map<String, Object?> state, String reference) {
    state['outbox'] = NoteBundleProjection.entries(state, 'outbox')
        .map(
          (m) =>
              NoteBundleProjection.reference(state, m, idField: 'noteId') ==
                  reference
              ? {...m, 'lastError': 'forbidden', 'blocked': true}
              : m,
        )
        .toList();
  }
}
