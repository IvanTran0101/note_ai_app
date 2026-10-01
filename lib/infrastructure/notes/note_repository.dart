import 'dart:async';

import '../../application/sync/local_note_state.dart';
import '../../application/sync/local_sync_state.dart';
import '../../application/sync/local_sync_store.dart';
import '../../application/sync/note_sync_status.dart';
import '../../application/sync/pending_mutation.dart';
import '../../application/sync/sync_conflict.dart';
import '../../application/sync/sync_failure.dart';
import '../../application/sync/sync_mutation.dart';
import '../../domain/notes/note.dart';
import '../../domain/notes/note_repository.dart' as domain;

/// Infrastructure implementation of the domain's [domain.INoteRepository].
///
/// The repository owns one account-scoped [ILocalSyncStore] per signed-in
/// account and keeps local notes and their outbox entries in the same
/// [LocalSyncState] document. Every mutation transforms the current document
/// through [ILocalSyncStore.update], so a note change and its queued mutation
/// stay atomic even when sync is writing a checkpoint at the same time.
///
/// All operations run through one FIFO queue. Reads therefore observe every
/// preceding mutation, and concurrent read-modify-write calls cannot overwrite
/// each other.
///
/// The repository never calls the remote data source: it only queues outbox
/// mutations that a later sync coordinator pushes.
final class NoteRepository implements domain.INoteRepository {
  /// Creates a repository from the injected account resolver, store factory,
  /// mutation-id generator, and clock.
  NoteRepository({
    required this.currentAccountUserId,
    required this.localSyncStoreFactory,
    required this.generateMutationId,
    required this.now,
  });

  /// Resolves the account the next operation acts on.
  final String Function() currentAccountUserId;

  /// Creates the account-bound local store on first use.
  final ILocalSyncStore Function({required String accountUserId})
  localSyncStoreFactory;

  /// Produces a new mutation id for an outbox entry.
  final String Function() generateMutationId;

  /// Supplies the local timestamp recorded on notes and mutations.
  final DateTime Function() now;

  /// One store instance per account, created on first use and reused after.
  final Map<String, ILocalSyncStore> _storesByAccount =
      <String, ILocalSyncStore>{};

  /// Serializes repository operations so concurrent read-modify-write calls
  /// cannot overwrite each other's changes.
  Future<void> _operationTail = Future<void>.value();

  @override
  Future<Note?> findById(String id) {
    return _enqueue<Note?>(() async {
      final LocalSyncState state = await _readActiveState();
      final LocalNoteState? note = _findNote(state, id);
      if (note == null || note.isDeleted) {
        return null;
      }
      return _toDomain(note);
    });
  }

  @override
  Future<List<Note>> findByOwnerId(String ownerId) {
    return _enqueue<List<Note>>(() async {
      final String accountUserId = _requireActiveAccountUserId();
      if (ownerId != accountUserId) {
        // The active account never exposes another owner's notes.
        return const <Note>[];
      }
      final LocalSyncState state = await _readStateFor(accountUserId);
      return List<Note>.unmodifiable(
        state.notes
            .where((LocalNoteState note) => !note.isDeleted)
            .map(_toDomain),
      );
    });
  }

  @override
  Future<void> save(Note note) {
    return _enqueue<void>(() async {
      final String accountUserId = _requireActiveAccountUserId();
      if (note.ownerId != accountUserId) {
        throw ArgumentError.value(
          note.ownerId,
          'note',
          'belongs to another account',
        );
      }
      final ILocalSyncStore store = _storeFor(accountUserId);
      await store.update((LocalSyncState current) {
        if (current.conflicts.any(
          (SyncConflict conflict) => conflict.noteId == note.id,
        )) {
          throw StateError(
            'Resolve the sync conflict before editing this note.',
          );
        }
        final LocalNoteState? existing = _findNote(current, note.id);
        if (existing?.isDeleted ?? false) {
          throw StateError(
            'A deleted note cannot be restored with the same id.',
          );
        }
        return _stateAfterSave(current, note, now());
      });
    });
  }

  @override
  Future<Note?> updateById(
    String id, {
    required String expectedAccountUserId,
    required void Function(Note note) change,
  }) {
    return _enqueue<Note?>(() async {
      final String accountUserId = _requireActiveAccountUserId();
      if (accountUserId != expectedAccountUserId) {
        throw StateError('The active account changed before the note update.');
      }
      final ILocalSyncStore store = _storeFor(accountUserId);
      Note? updated;
      await store.update((LocalSyncState current) {
        if (current.accountUserId != expectedAccountUserId ||
            currentAccountUserId() != expectedAccountUserId) {
          throw StateError(
            'The active account changed before the note update.',
          );
        }
        if (current.conflicts.any(
          (SyncConflict conflict) => conflict.noteId == id,
        )) {
          throw StateError(
            'Resolve the sync conflict before editing this note.',
          );
        }
        final LocalNoteState? existing = _findNote(current, id);
        if (existing == null || existing.isDeleted) return current;
        final Note fresh = _toDomain(existing);
        change(fresh);
        updated = fresh;
        if (fresh.title == existing.title &&
            fresh.content == existing.content &&
            fresh.pinnedAt == existing.pinnedAt &&
            fresh.updatedAt == existing.updatedAt) {
          return current;
        }
        return _stateAfterSave(current, fresh, now());
      });
      return updated;
    });
  }

  @override
  Future<void> deleteById(String id) {
    return _enqueue<void>(() async {
      final String accountUserId = _requireActiveAccountUserId();
      final ILocalSyncStore store = _storeFor(accountUserId);
      await store.update((LocalSyncState current) {
        if (current.conflicts.any(
          (SyncConflict conflict) => conflict.noteId == id,
        )) {
          throw StateError(
            'Resolve the sync conflict before deleting this note.',
          );
        }
        final LocalNoteState? existing = _findNote(current, id);
        if (existing == null || existing.isDeleted) {
          // An absent or already tombstoned note is already deleted.
          return current;
        }
        final int pendingIndex = _lastPendingIndexFor(current, id);
        final PendingMutation? pending = pendingIndex == -1
            ? null
            : current.outbox[pendingIndex];
        if (existing.serverRevision == 0 && pending == null) {
          // No server version and no queued create means this note is only a
          // local draft. Removing it locally cannot lose a remote delete.
          return _stateWith(
            current,
            notes: current.notes
                .where((LocalNoteState note) => note.id != id)
                .toList(growable: false),
            outbox: current.outbox,
          );
        }
        if (pending != null &&
            pending.operation == SyncMutationOperation.create &&
            existing.serverRevision == 0 &&
            _isUnsent(pending)) {
          // The create never reached the server, so dropping the note and its
          // mutation is the whole delete: no remote tombstone is needed.
          return _stateWith(
            current,
            notes: current.notes
                .where((LocalNoteState note) => note.id != id)
                .toList(growable: false),
            outbox: current.outbox
                .where(
                  (PendingMutation entry) =>
                      entry.mutationId != pending.mutationId,
                )
                .toList(growable: false),
          );
        }
        final DateTime timestamp = now();
        final LocalNoteState tombstone = LocalNoteState(
          id: existing.id,
          ownerId: existing.ownerId,
          title: '',
          content: '',
          createdAt: existing.createdAt,
          updatedAt: timestamp,
          pinnedAt: existing.pinnedAt,
          serverRevision: existing.serverRevision,
          deletedAt: timestamp,
          status: NoteSyncStatus.pending,
        );
        return _stateWith(
          current,
          notes: _notesWith(current.notes, tombstone),
          outbox: _outboxAfterDelete(
            current,
            existing,
            pendingIndex,
            timestamp,
          ),
        );
      });
    });
  }

  Future<LocalSyncState> _readActiveState() {
    return _readStateFor(_requireActiveAccountUserId());
  }

  Future<LocalSyncState> _readStateFor(String accountUserId) async {
    final LocalSyncState state = await _storeFor(accountUserId).read();
    if (state.accountUserId != accountUserId) {
      throw StateError('The local sync store returned another account state.');
    }
    return state;
  }

  /// Resolves the account the current operation belongs to, failing closed when
  /// no account is signed in.
  String _requireActiveAccountUserId() {
    final String accountUserId = currentAccountUserId();
    if (accountUserId.trim().isEmpty) {
      throw StateError('No signed-in account is available for local notes.');
    }
    return accountUserId;
  }

  ILocalSyncStore _storeFor(String accountUserId) {
    return _storesByAccount.putIfAbsent(
      accountUserId,
      () => localSyncStoreFactory(accountUserId: accountUserId),
    );
  }

  LocalSyncState _stateAfterSave(
    LocalSyncState current,
    Note note,
    DateTime timestamp,
  ) {
    final LocalNoteState? existing = _findNote(current, note.id);
    if (existing == null) {
      // A new local note starts unacknowledged and queues one create.
      return _stateWith(
        current,
        notes: <LocalNoteState>[
          ...current.notes,
          _toLocalNote(note, serverRevision: 0, status: NoteSyncStatus.pending),
        ],
        outbox: <PendingMutation>[
          ...current.outbox,
          _pendingMutation(
            noteId: note.id,
            operation: SyncMutationOperation.create,
            baseRevision: 0,
            payload: _payloadOf(note),
            timestamp: timestamp,
          ),
        ],
      );
    }
    return _stateWith(
      current,
      notes: _notesWith(
        current.notes,
        _toLocalNote(
          note,
          serverRevision: existing.serverRevision,
          status: NoteSyncStatus.pending,
        ),
      ),
      outbox: _outboxAfterSave(current, note, existing, timestamp),
    );
  }

  List<PendingMutation> _outboxAfterSave(
    LocalSyncState current,
    Note note,
    LocalNoteState existing,
    DateTime timestamp,
  ) {
    final SyncNotePayload payload = _payloadOf(note);
    if (current.outbox.any(
      (PendingMutation entry) =>
          entry.noteId == note.id &&
          entry.blocked &&
          entry.lastError == SyncErrorCode.invalidMutation,
    )) {
      // An explicit edit repairs a rejected request with a fresh id and the
      // last acknowledged revision; successors of that request cannot run.
      return <PendingMutation>[
        ...current.outbox.where(
          (PendingMutation entry) => entry.noteId != note.id,
        ),
        _pendingMutation(
          noteId: note.id,
          operation: existing.serverRevision == 0
              ? SyncMutationOperation.create
              : SyncMutationOperation.update,
          baseRevision: existing.serverRevision,
          payload: payload,
          timestamp: timestamp,
        ),
      ];
    }
    final int index = _lastPendingIndexFor(current, note.id);
    if (index == -1) {
      // Nothing is queued yet: base the update on the acknowledged revision.
      return <PendingMutation>[
        ...current.outbox,
        _pendingMutation(
          noteId: note.id,
          operation: SyncMutationOperation.update,
          baseRevision: existing.serverRevision,
          payload: payload,
          timestamp: timestamp,
        ),
      ];
    }
    final PendingMutation last = current.outbox[index];
    if (last.operation == SyncMutationOperation.delete) {
      throw StateError('A queued delete cannot be undone with the same id.');
    }
    if (!_isUnsent(last)) {
      // The entry may already have been seen by the server, so it stays
      // byte-for-byte identical and the edit becomes the next queued mutation
      // at the next predicted revision. Its id remains stable for retries.
      return <PendingMutation>[
        ...current.outbox,
        _pendingMutation(
          noteId: note.id,
          operation: SyncMutationOperation.update,
          baseRevision: last.baseRevision + 1,
          payload: payload,
          timestamp: timestamp,
        ),
      ];
    }
    // Unsent coalescing keeps the queue position, the base revision, and the
    // mutation id, while the payload always reflects the latest edit.
    final PendingMutation coalesced = PendingMutation(
      mutationId: last.mutationId,
      noteId: note.id,
      operation: last.operation,
      baseRevision: last.baseRevision,
      payload: payload,
      createdAt: last.createdAt,
    );
    return _outboxWithReplacement(current.outbox, index, coalesced);
  }

  List<PendingMutation> _outboxAfterDelete(
    LocalSyncState current,
    LocalNoteState note,
    int pendingIndex,
    DateTime timestamp,
  ) {
    if (pendingIndex == -1) {
      return <PendingMutation>[
        ...current.outbox,
        _pendingMutation(
          noteId: note.id,
          operation: SyncMutationOperation.delete,
          baseRevision: note.serverRevision,
          timestamp: timestamp,
        ),
      ];
    }
    final PendingMutation last = current.outbox[pendingIndex];
    if (last.operation == SyncMutationOperation.delete) {
      // The delete is already queued; a second one would be redundant.
      return current.outbox;
    }
    if (!_isUnsent(last)) {
      return <PendingMutation>[
        ...current.outbox,
        _pendingMutation(
          noteId: note.id,
          operation: SyncMutationOperation.delete,
          baseRevision: last.baseRevision + 1,
          timestamp: timestamp,
        ),
      ];
    }
    // Unsent coalescing: an update followed by a delete is just the delete,
    // reusing the mutation id and base revision the server has never seen.
    final int baseRevision = last.operation == SyncMutationOperation.create
        ? note.serverRevision
        : last.baseRevision;
    return _outboxWithReplacement(
      current.outbox,
      pendingIndex,
      PendingMutation(
        mutationId: last.mutationId,
        noteId: note.id,
        operation: SyncMutationOperation.delete,
        baseRevision: baseRevision,
        createdAt: last.createdAt,
      ),
    );
  }

  PendingMutation _pendingMutation({
    required String noteId,
    required SyncMutationOperation operation,
    required int baseRevision,
    SyncNotePayload? payload,
    required DateTime timestamp,
  }) {
    return PendingMutation(
      mutationId: generateMutationId(),
      noteId: noteId,
      operation: operation,
      baseRevision: baseRevision,
      payload: payload,
      createdAt: timestamp,
    );
  }

  /// True when the entry has never been pushed, so it can still be rewritten.
  ///
  /// An attempted or blocked entry may already be in flight (or applied with a
  /// lost response), and the server rejects reuse of its id with a changed
  /// request.
  static bool _isUnsent(PendingMutation entry) {
    return entry.retryCount == 0 && !entry.blocked;
  }

  static LocalNoteState? _findNote(LocalSyncState state, String id) {
    for (final LocalNoteState note in state.notes) {
      if (note.id == id) {
        return note;
      }
    }
    return null;
  }

  /// Index of the newest outbox entry for [noteId], or -1 when none exists.
  static int _lastPendingIndexFor(LocalSyncState state, String noteId) {
    for (int index = state.outbox.length - 1; index >= 0; index--) {
      if (state.outbox[index].noteId == noteId) {
        return index;
      }
    }
    return -1;
  }

  static List<LocalNoteState> _notesWith(
    List<LocalNoteState> notes,
    LocalNoteState replacement,
  ) {
    final int index = notes.indexWhere(
      (LocalNoteState note) => note.id == replacement.id,
    );
    if (index == -1) {
      return <LocalNoteState>[...notes, replacement];
    }
    final List<LocalNoteState> copy = List<LocalNoteState>.of(notes);
    copy[index] = replacement;
    return copy;
  }

  static List<PendingMutation> _outboxWithReplacement(
    List<PendingMutation> outbox,
    int index,
    PendingMutation replacement,
  ) {
    final List<PendingMutation> copy = List<PendingMutation>.of(outbox);
    copy[index] = replacement;
    return copy;
  }

  /// Copies a state while replacing only the notes and outbox.
  static LocalSyncState _stateWith(
    LocalSyncState current, {
    required List<LocalNoteState> notes,
    required List<PendingMutation> outbox,
  }) {
    return LocalSyncState(
      accountUserId: current.accountUserId,
      notes: notes,
      outbox: outbox,
      conflicts: current.conflicts,
      cursor: current.cursor,
      userPreferences: current.userPreferences,
    );
  }

  static SyncNotePayload _payloadOf(Note note) {
    return SyncNotePayload(
      title: note.title,
      content: note.content,
      pinnedAt: note.pinnedAt,
      includesPinnedAt: true,
    );
  }

  static LocalNoteState _toLocalNote(
    Note note, {
    required int serverRevision,
    required NoteSyncStatus status,
  }) {
    return LocalNoteState(
      id: note.id,
      ownerId: note.ownerId,
      title: note.title,
      content: note.content,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      pinnedAt: note.pinnedAt,
      serverRevision: serverRevision,
      status: status,
    );
  }

  static Note _toDomain(LocalNoteState note) {
    return Note.reconstitute(
      id: note.id,
      ownerId: note.ownerId,
      title: note.title,
      content: note.content,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      pinnedAt: note.pinnedAt,
    );
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final Future<void> previous = _operationTail;
    final Completer<void> release = Completer<void>();
    _operationTail = release.future;
    return previous.then((_) => operation()).whenComplete(release.complete);
  }
}

/// Creates the local-first Note repository.
///
/// The composition root injects the active account resolver, the account-bound
/// local sync store factory, the mutation-id generator, and the clock. Tests
/// inject fakes. The repository stays offline-safe: it never calls the remote
/// data source.
domain.INoteRepository createNoteRepository({
  required String Function() currentAccountUserId,
  required ILocalSyncStore Function({required String accountUserId})
  localSyncStoreFactory,
  required String Function() generateMutationId,
  required DateTime Function() now,
}) {
  return NoteRepository(
    currentAccountUserId: currentAccountUserId,
    localSyncStoreFactory: localSyncStoreFactory,
    generateMutationId: generateMutationId,
    now: now,
  );
}
