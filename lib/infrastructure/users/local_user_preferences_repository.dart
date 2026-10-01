import '../../application/sync/local_sync_state.dart';
import '../../application/sync/local_sync_store.dart';
import '../../domain/users/user_preferences.dart';
import '../../domain/users/user_preferences_repository.dart';

/// Stores account-local preferences in the account's existing atomic envelope.
final class LocalUserPreferencesRepository
    implements IUserPreferencesRepository {
  LocalUserPreferencesRepository({
    required this.currentAccountUserId,
    required this.localSyncStoreFactory,
  });

  final String Function() currentAccountUserId;
  final ILocalSyncStore Function({required String accountUserId})
  localSyncStoreFactory;
  final Map<String, ILocalSyncStore> _stores = <String, ILocalSyncStore>{};

  @override
  Future<UserPreferences?> findByUserId(String userId) async {
    final String accountUserId = currentAccountUserId();
    if (accountUserId.isEmpty || userId != accountUserId) return null;
    final LocalSyncState state = await _store(accountUserId).read();
    if (state.accountUserId != accountUserId) {
      throw StateError('The local preference store returned another account.');
    }
    return state.userPreferences;
  }

  @override
  Future<void> save(UserPreferences preferences) async {
    final String accountUserId = currentAccountUserId();
    if (accountUserId.isEmpty || preferences.userId != accountUserId) {
      throw ArgumentError.value(
        preferences.userId,
        'preferences',
        'belongs to another account',
      );
    }
    await _store(accountUserId).update((LocalSyncState current) {
      if (current.accountUserId != accountUserId ||
          currentAccountUserId() != accountUserId) {
        throw StateError(
          'The active account changed before saving preferences.',
        );
      }
      return LocalSyncState(
        accountUserId: current.accountUserId,
        notes: current.notes,
        outbox: current.outbox,
        conflicts: current.conflicts,
        cursor: current.cursor,
        userPreferences: preferences,
      );
    });
  }

  ILocalSyncStore _store(String accountUserId) => _stores.putIfAbsent(
    accountUserId,
    () => localSyncStoreFactory(accountUserId: accountUserId),
  );
}

IUserPreferencesRepository createLocalUserPreferencesRepository({
  required String Function() currentAccountUserId,
  required ILocalSyncStore Function({required String accountUserId})
  localSyncStoreFactory,
}) => LocalUserPreferencesRepository(
  currentAccountUserId: currentAccountUserId,
  localSyncStoreFactory: localSyncStoreFactory,
);
