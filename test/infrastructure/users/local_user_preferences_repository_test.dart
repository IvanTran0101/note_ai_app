import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/local_sync_store.dart';
import 'package:note_ai_app/domain/users/user_preferences.dart';
import 'package:note_ai_app/infrastructure/users/local_user_preferences_repository.dart';

final class _MemoryStore implements ILocalSyncStore {
  _MemoryStore(String accountUserId)
    : state = LocalSyncState(accountUserId: accountUserId);

  LocalSyncState state;
  void Function()? beforeUpdate;

  @override
  Future<LocalSyncState> read() async => state;

  @override
  Future<LocalSyncState> update(
    LocalSyncState Function(LocalSyncState current) transform,
  ) async {
    beforeUpdate?.call();
    return state = transform(state);
  }

  @override
  Future<void> replace(LocalSyncState value) async => state = value;
}

void main() {
  test('same-account relogin cancels a queued preference write', () async {
    var generation = 1;
    final store = _MemoryStore('account-a');
    final repository = LocalUserPreferencesRepository(
      currentAccountUserId: () => 'account-a',
      sessionGeneration: () => generation,
      localSyncStoreFactory: ({required accountUserId}) => store,
    );
    store.beforeUpdate = () => generation++;
    await expectLater(
      repository.save(
        UserPreferences.create(
          userId: 'account-a',
          theme: AppThemePreference.system,
          noteFontSize: NoteFontSizePreference.medium,
          noteLayout: NoteLayoutPreference.list,
        ),
      ),
      throwsStateError,
    );
    expect(store.state.userPreferences.noteLayout, NoteLayoutPreference.grid);
  });
  test('stores note layout in the matching account state', () async {
    String activeAccount = 'account-a';
    final Map<String, _MemoryStore> stores = <String, _MemoryStore>{};
    final LocalUserPreferencesRepository repository =
        LocalUserPreferencesRepository(
          currentAccountUserId: () => activeAccount,
          localSyncStoreFactory: ({required String accountUserId}) => stores
              .putIfAbsent(accountUserId, () => _MemoryStore(accountUserId)),
        );

    final UserPreferences preferences = UserPreferences.create(
      userId: 'account-a',
      theme: AppThemePreference.system,
      noteFontSize: NoteFontSizePreference.medium,
      noteLayout: NoteLayoutPreference.list,
    );
    await repository.save(preferences);

    expect(
      (await repository.findByUserId('account-a'))?.noteLayout,
      NoteLayoutPreference.list,
    );
    expect(await repository.findByUserId('account-b'), isNull);

    activeAccount = 'account-b';
    expect(
      (await repository.findByUserId('account-b'))?.noteLayout,
      NoteLayoutPreference.grid,
    );
    await expectLater(repository.save(preferences), throwsArgumentError);
  });
}
