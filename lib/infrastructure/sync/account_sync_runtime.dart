import 'dart:async';

import '../../application/sync/local_sync_store.dart';
import '../../application/sync/sync_coordinator_service.dart';
import '../../application/sync/sync_report.dart';
import 'cognito_access_token_provider.dart';
import 'http_remote_note_data_source.dart';

/// Creates one remote/coordinator pair per Cognito account for the app session.
///
/// The API adapter checks the access token's `sub` against the account-bound
/// local store before sending note data, so an account switch cannot upload one
/// user's outbox under another user's token.
final class AccountSyncRuntime {
  AccountSyncRuntime({
    required this.baseUri,
    required this.localSyncStoreFactory,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Uri baseUri;
  final ILocalSyncStore Function({required String accountUserId})
  localSyncStoreFactory;
  final DateTime Function() _clock;
  final Map<String, SyncCoordinatorService> _coordinators =
      <String, SyncCoordinatorService>{};
  final Map<String, HttpRemoteNoteDataSource> _remoteDataSources =
      <String, HttpRemoteNoteDataSource>{};

  /// Returns the account-bound coordinator, creating it on first use.
  SyncCoordinatorService coordinatorFor(String accountUserId) {
    if (accountUserId.trim().isEmpty) {
      throw ArgumentError.value(accountUserId, 'accountUserId');
    }
    return _coordinators.putIfAbsent(accountUserId, () {
      final HttpRemoteNoteDataSource remote = HttpRemoteNoteDataSource(
        baseUri: baseUri,
        tokenProvider: const CognitoAccessTokenProvider().call,
        expectedAccountUserId: accountUserId,
      );
      _remoteDataSources[accountUserId] = remote;
      return SyncCoordinatorService(
        accountUserId: accountUserId,
        localStore: localSyncStoreFactory(accountUserId: accountUserId),
        remote: remote,
        clock: _clock,
      );
    });
  }

  /// Starts sync without making local note/auth actions wait for the network.
  void requestSync(String accountUserId) {
    unawaited(_syncBestEffort(accountUserId));
  }

  /// Exposes a manual/run-to-completion path for future sync UI and tests.
  Future<SyncReport> syncNow(String accountUserId) {
    return coordinatorFor(accountUserId).syncNow();
  }

  Future<void> _syncBestEffort(String accountUserId) async {
    try {
      await syncNow(accountUserId);
    } on Object {
      // Failure remains available through the coordinator's status stream.
    }
  }

  Future<void> dispose() async {
    for (final HttpRemoteNoteDataSource remote in _remoteDataSources.values) {
      remote.close();
    }
    await Future.wait<void>(
      _coordinators.values.map((SyncCoordinatorService item) => item.dispose()),
    );
  }
}
