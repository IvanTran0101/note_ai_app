import 'dart:async';
import 'dart:convert';

import '../../application/notes/local_first_note_vault.dart';
import '../../application/sync/local_protection_queue.dart';
import '../../application/sync/protection_sync_change.dart';

import '../../application/notes/local_note_vault.dart';
import '../../application/notes/local_draft_vault.dart';
import '../../application/notes/note_dto.dart';
import '../../application/notes/note_access.dart';
import '../../application/sync/local_note_state.dart';
import '../../application/sync/local_sync_state.dart';
import '../../application/sync/local_sync_store.dart';
import '../../application/sync/note_sync_status.dart';
import '../../application/sync/sync_snapshot.dart';
import '../../application/sync/sync_conflict.dart';
import '../../domain/notes/note_protection.dart';
import '../sync/local_sync_store_account_namespace.dart';
import 'encoded_account_store.dart';
import 'encrypted_state_codec.dart';

/// One queue freezes all reads, updates and AI source access during migration.
/// Cross-context races use CAS; a migration failure never seeds an empty state.
part 'encrypted_local_protection.dart';

class EncryptedSyncStore
    implements
        ILocalSyncStore,
        ILocalNoteVault,
        ILocalFirstNoteVault,
        ILocalDraftVault {
  EncryptedSyncStore(String accountId, this.backing)
    : codec = EncryptedStateCodec(LocalSyncAccountNamespace(accountId));
  final EncodedAccountStore backing;
  final EncryptedStateCodec codec;
  Future<void> _tail = Future<void>.value();

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    return previous.then((_) async {
      try {
        return await action();
      } finally {
        release.complete();
      }
    });
  }

  Future<LocalSyncState> _read() async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final encoded = await backing.readEncoded();
      final state = await codec.decode(encoded);
      if (!codec.migrationRequired) {
        if (encoded != null) {
          await backing.cleanLegacyStaging(
            codec.namespace.accountUserId,
            codec.sealLegacyStaging,
          );
        }
        return state;
      }
      final sealed = await codec.encode(state);
      if (await backing.compareAndSet(encoded, sealed)) {
        await backing.cleanLegacyStaging(
          codec.namespace.accountUserId,
          codec.sealLegacyStaging,
        );
        return state;
      }
    }
    throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
  }

  Future<LocalSyncState> _mutate(
    Future<LocalSyncState> Function(LocalSyncState) transform,
  ) async {
    await _read(); // Completes cutover before any caller transform may run.
    for (var attempt = 0; attempt < 5; attempt++) {
      final encoded = await backing.readEncoded();
      final current = await codec.decode(encoded);
      final transformed = await transform(current);
      final next = await codec.retainAccessChanges(current, transformed);
      codec.namespace.requireOwned(next);
      final start = codec.generation;
      final sealed = await codec.encode(next);
      if (start != codec.generation) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
      }
      if (await backing.compareAndSet(encoded, sealed)) return next;
    }
    throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
  }

  @override
  Future<LocalSyncState> read() => _enqueue(_read);
  @override
  Future<void> replace(LocalSyncState state) => _enqueue(() async {
    await _mutate((_) async => state);
  });
  @override
  Future<LocalSyncState> update(
    LocalSyncState Function(LocalSyncState) transform,
  ) => _enqueue(() => _mutate((state) async => transform(state)));

  @override
  Future<void> retainEditorDraft(
    NoteDto selected,
    String title,
    String content,
  ) => _enqueue(() async {
    await _mutate((state) async {
      await codec.retainEditorEvidence(selected, title, content);
      return state;
    });
  });

  @override
  Future<NoteProtection> enableLocal(String id, String password) =>
      _localProtection(id, null, password, enable: true);
  @override
  Future<NoteProtection> changeLocal(String id, String current, String next) =>
      _localProtection(id, current, next, enable: true);
  @override
  Future<NoteProtection> disableLocal(String id, String current) =>
      _localProtection(id, current, null, enable: false);

  @override
  Future<void> seal(String id, String password, NoteProtection p) =>
      _enqueue(() async {
        await _mutate((state) => codec.seal(state, id, password, p));
      });
  @override
  Future<void> unlock(
    String id,
    String password,
    NoteProtection p, {
    bool verifiedOnline = false,
  }) => _enqueue(() async {
    await _mutate(
      (state) =>
          codec.unlock(state, id, password, p, verifiedOnline: verifiedOnline),
    );
  });
  @override
  Future<void> rewrap(
    String id,
    String oldPassword,
    String newPassword,
    NoteProtection p,
  ) => _enqueue(() async {
    await _mutate(
      (state) => codec.rewrap(state, id, oldPassword, newPassword, p),
    );
  });
  @override
  Future<void> disable(String id, String password, NoteProtection p) =>
      _enqueue(() async {
        await _mutate((state) => codec.disable(state, id, password, p));
      });
  @override
  Future<void> observeProtection(String id, NoteProtection p) =>
      _enqueue(() async {
        await _mutate((state) async {
          final old = state.notes
              .where((n) => n.referenceFor(state.accountUserId) == id)
              .firstOrNull;
          if (old != null && old.protection != p) codec.lock(id);
          final reconciled = await codec.observe(state, id, p);
          return EncryptedStateCodec.changeMetadata(reconciled, id, p);
        });
      });
  @override
  Future<void> hydrate(SyncNoteSnapshot snapshot) => _enqueue(() async {
    final identity = snapshot.identityFor(codec.namespace.accountUserId);
    final reference = identity.referenceFor(codec.namespace.accountUserId);
    if (snapshot.accessRemoved ||
        !snapshot.contentAvailable ||
        (snapshot.protection.enabled &&
            !codec.isUnlocked(reference, snapshot.protection))) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
    }
    await _mutate((state) async {
      final current = state.notes
          .where((n) => n.identity == identity)
          .firstOrNull;
      final pending = state.outbox.any(
        (m) => m.mutation.identityFor(state.accountUserId) == identity,
      );
      final hydrated = LocalNoteState(
        id: snapshot.id,
        ownerId: identity.ownerId,
        share: snapshot.share,
        title: pending && current?.contentAvailable == true
            ? current!.title
            : snapshot.title,
        content: pending && current?.contentAvailable == true
            ? current!.content
            : snapshot.content,
        createdAt: current?.createdAt ?? snapshot.createdAt,
        updatedAt: pending
            ? current?.updatedAt ?? snapshot.serverUpdatedAt
            : snapshot.serverUpdatedAt,
        serverRevision: pending
            ? current?.serverRevision ?? snapshot.revision
            : snapshot.revision,
        deletedAt: snapshot.deletedAt,
        protection: snapshot.protection,
        status: current?.status ?? NoteSyncStatus.synced,
      );
      return LocalSyncState(
        accountUserId: state.accountUserId,
        notes: [...state.notes.where((n) => n.identity != identity), hydrated],
        outbox: state.outbox,
        conflicts: state.conflicts.map(
          (c) =>
              c.identity == identity &&
                  (c.remote?.revision ?? 0) <= snapshot.revision
              ? SyncConflict(
                  noteId: c.noteId,
                  local: c.local,
                  pending: c.pending,
                  detectedAt: c.detectedAt,
                  remote: snapshot,
                )
              : c,
        ),
        cursor: state.cursor,
      );
    });
  });
  @override
  bool isLocallyUnlocked(String id, NoteProtection p) =>
      codec.isUnlocked(id, p);
  @override
  bool hasRetainedCiphertext(String id) => codec.hasRetained(id);
  @override
  void lock(String? id) => codec.lock(id);
  @override
  void dispose() => codec.dispose();
}
