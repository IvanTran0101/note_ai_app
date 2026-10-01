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
import '../../domain/notes/note_metadata.dart';
import '../../domain/notes/note_protection.dart';
import '../../domain/notes/note_repository.dart' as domain;

part 'note_repository_mutations.dart';

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
final class NoteRepository
    implements domain.INoteRepository, domain.INoteMetadataRepository {
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
            .map(
              (note) => _toDomain(note, metadataOnly: note.protection.enabled),
            ),
      );
    });
  }

  @override
  Future<NoteMetadata?> findMetadataById(String id) async {
    final Note? note = await findById(id);
    return note?.metadata;
  }

  @override
  Future<List<NoteMetadata>> findMetadataByOwnerId(String ownerId) async =>
      (await findByOwnerId(ownerId))
          .map((note) => note.metadata)
          .toList(growable: false);

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
        if (!note.contentAvailable ||
            (existing != null && !existing.contentAvailable)) {
          throw const NoteContentUnavailable();
        }
        if (existing != null && existing.protection != note.protection) {
          throw StateError('Refresh note protection before saving.');
        }
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
        if (!existing.contentAvailable) throw const NoteContentUnavailable();
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
          serverRevision: existing.serverRevision,
          deletedAt: timestamp,
          status: NoteSyncStatus.pending,
          protection: existing.protection,
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
    );
  }

  static SyncNotePayload _payloadOf(Note note) {
    return SyncNotePayload(title: note.title, content: note.content);
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
      serverRevision: serverRevision,
      status: status,
      protection: note.protection,
      contentAvailable: note.contentAvailable,
    );
  }

  static Note _toDomain(LocalNoteState note, {bool metadataOnly = false}) {
    final bool available = note.contentAvailable && !metadataOnly;
    return Note.reconstitute(
      id: note.id,
      ownerId: note.ownerId,
      title: available ? note.title : '',
      content: available ? note.content : '',
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      protection: note.protection,
      contentAvailable: available,
      contentRevision: note.serverRevision,
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
