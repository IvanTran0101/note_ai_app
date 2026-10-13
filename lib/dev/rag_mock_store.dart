/// The smallest debug-only in-memory sync store for the offline RAG mock.
///
/// It persists nothing: state lives in one field for the lifetime of the debug
/// run, so no disk, IndexedDB, or provider is ever touched. It implements both
/// the Application store port and the local protection port because the existing
/// composition asks for the vault whenever a security service is created; the
/// protection operations are inert and refuse crypto work, since the fixture is
/// explicitly unprotected.
library;

import '../application/notes/local_note_vault.dart';
import '../application/sync/local_note_state.dart';
import '../application/sync/local_sync_state.dart';
import '../application/sync/local_sync_store.dart';
import '../application/sync/sync_snapshot.dart';
import '../domain/notes/note_protection.dart';
import 'rag_mock_actors.dart';
import 'rag_mock_fixture.dart';

final class RagMockMemoryStore implements ILocalSyncStore, ILocalNoteVault {
  /// Seeds the store with [actor]'s single synthetic fixture note.
  RagMockMemoryStore.forActor(RagMockActor actor)
    : _state = _seededState(actor);

  /// Creates an empty state for an id the mock root never selected.
  RagMockMemoryStore.empty({required String accountUserId})
    : _state = LocalSyncState(accountUserId: accountUserId);

  LocalSyncState _state;

  @override
  Future<LocalSyncState> read() async => _state;

  @override
  Future<LocalSyncState> update(
    LocalSyncState Function(LocalSyncState current) transform,
  ) async {
    final LocalSyncState next = transform(_state);
    _state = next;
    return next;
  }

  @override
  Future<void> replace(LocalSyncState state) async {
    _state = state;
  }

  // The fixture is unprotected, so no protection path is exercised. These
  // methods exist only so the existing security composition can be assembled;
  // they deliberately refuse rather than pretending to encrypt.
  @override
  Future<void> seal(
    String noteId,
    String password,
    NoteProtection protection,
  ) => _readOnly();

  @override
  Future<void> unlock(
    String noteId,
    String password,
    NoteProtection protection, {
    bool verifiedOnline = false,
  }) => _readOnly();

  @override
  Future<void> rewrap(
    String noteId,
    String currentPassword,
    String newPassword,
    NoteProtection protection,
  ) => _readOnly();

  @override
  Future<void> disable(
    String noteId,
    String password,
    NoteProtection protection,
  ) => _readOnly();

  @override
  Future<void> observeProtection(
    String noteId,
    NoteProtection protection,
  ) async {}

  @override
  Future<void> hydrate(SyncNoteSnapshot snapshot) async {}

  @override
  bool isLocallyUnlocked(String noteId, NoteProtection protection) => false;

  @override
  bool hasRetainedCiphertext(String noteId) => false;

  @override
  void lock(String? noteId) {}

  @override
  void dispose() {}

  Never _readOnly() =>
      throw UnsupportedError('The offline RAG mock store is read-only.');
}

LocalSyncState _seededState(RagMockActor actor) {
  final RagMockFixture fixture = ragMockFixtureFor(actor);
  final DateTime created = DateTime.utc(2026, 1, 1);
  return LocalSyncState(
    accountUserId: actor.userId,
    notes: <LocalNoteState>[
      LocalNoteState(
        id: fixture.noteId,
        ownerId: actor.userId,
        title: fixture.title,
        content: fixture.content,
        createdAt: created,
        updatedAt: created,
        serverRevision: fixture.serverRevision,
      ),
    ],
  );
}
