import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/local_sync_store.dart';
import 'package:note_ai_app/application/sync/sync_cursor.dart';

final DateTime _createdAt = DateTime.utc(2026, 9, 25, 9);

LocalNoteState _note({String ownerId = 'user-1'}) {
  return LocalNoteState(
    id: 'note-1',
    ownerId: ownerId,
    title: 'Title',
    content: 'Content',
    createdAt: _createdAt,
    updatedAt: _createdAt,
  );
}

/// Minimal in-memory implementation used only to pin the port's behavior.
///
/// It is deliberately not a production store: a real adapter owns durability.
final class _InMemoryLocalSyncStore implements ILocalSyncStore {
  _InMemoryLocalSyncStore({required this.accountUserId}) {
    _state = LocalSyncState(accountUserId: accountUserId);
  }

  final String accountUserId;
  late LocalSyncState _state;

  @override
  Future<LocalSyncState> read() async => _state;

  @override
  Future<LocalSyncState> update(
    LocalSyncState Function(LocalSyncState current) transform,
  ) async {
    final LocalSyncState next = transform(_state);
    if (next.accountUserId != accountUserId) {
      throw StateError('refusing to store another account state');
    }
    _state = next;
    return next;
  }

  @override
  Future<void> replace(LocalSyncState state) async {
    if (state.accountUserId != accountUserId) {
      throw StateError('refusing to store another account state');
    }
    _state = state;
  }
}

void main() {
  test('reads an empty account state before anything is stored', () async {
    final _InMemoryLocalSyncStore store = _InMemoryLocalSyncStore(
      accountUserId: 'user-1',
    );

    final LocalSyncState state = await store.read();

    expect(state.accountUserId, 'user-1');
    expect(state.isEmpty, isTrue);
    expect(state.cursor, isNull);
  });

  test('read returns the state replace persisted, without aliasing', () async {
    final _InMemoryLocalSyncStore store = _InMemoryLocalSyncStore(
      accountUserId: 'user-1',
    );
    final List<LocalNoteState> notes = <LocalNoteState>[_note()];
    final LocalSyncState state = LocalSyncState(
      accountUserId: 'user-1',
      notes: notes,
      cursor: const SyncCursor('c-1'),
    );

    await store.replace(state);
    notes.clear();

    final LocalSyncState stored = await store.read();

    expect(stored, state);
    expect(stored.notes, hasLength(1));
    expect(stored.cursor?.value, 'c-1');
  });

  test('a rejected replace leaves the previous state whole', () async {
    final _InMemoryLocalSyncStore store = _InMemoryLocalSyncStore(
      accountUserId: 'user-1',
    );
    final LocalSyncState first = LocalSyncState(
      accountUserId: 'user-1',
      notes: <LocalNoteState>[_note()],
    );
    await store.replace(first);

    await expectLater(
      store.replace(LocalSyncState(accountUserId: 'user-2')),
      throwsStateError,
    );

    expect(await store.read(), first);
  });

  test('the port is implementable without a storage provider', () {
    expect(
      _InMemoryLocalSyncStore(accountUserId: 'user-1'),
      isA<ILocalSyncStore>(),
    );
  });
}
