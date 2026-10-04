import '../../application/sync/sync_mutation.dart';
import '../../application/sync/local_note_state.dart';
import '../../application/sync/sync_snapshot.dart';
import '../../application/sync/sync_failure.dart';

import 'dart:async';

import 'package:http/http.dart' as http;

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
    this.mutationGrant,
    this.observeSnapshot,
    this.hydrateSnapshot,
    this.requireSession,
    this.sessionGeneration,
    SyncAccessTokenProvider? tokenProvider,
    this.client,
    this.labelsEnabled = false,
    this.projectionGrant,
    this.onCatalogChanged,
  }) : _clock = clock ?? DateTime.now,
       tokenProvider = tokenProvider ?? const CognitoAccessTokenProvider().call;

  final Uri baseUri;
  final bool labelsEnabled;
  final void Function(String actor)? onCatalogChanged;
  final String? Function(String account, LocalNoteState note)? projectionGrant;
  final SyncAccessTokenProvider tokenProvider;
  final http.Client? client;
  final Future<String?> Function(String account, SyncMutation mutation)?
  mutationGrant;
  final Future<void> Function(String account, SyncNoteSnapshot snapshot)?
  observeSnapshot;
  final Future<void> Function(String account, SyncNoteSnapshot snapshot)?
  hydrateSnapshot;
  final void Function(String account)? requireSession;
  final int Function()? sessionGeneration;
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
      final captured = sessionGeneration?.call();
      void requireLive() {
        requireSession?.call(accountUserId);
        if (captured != sessionGeneration?.call()) {
          throw const SyncFailure(code: SyncErrorCode.forbidden);
        }
      }

      final HttpRemoteNoteDataSource remote = HttpRemoteNoteDataSource(
        baseUri: baseUri,
        labelsEnabled: labelsEnabled,
        projectionGrant: (note) => projectionGrant?.call(accountUserId, note),
        tokenProvider: tokenProvider,
        client: client,
        expectedAccountUserId: accountUserId,
        requireSession: requireLive,
        mutationGrant: (mutation) async =>
            mutationGrant?.call(accountUserId, mutation),
      );
      _remoteDataSources[accountUserId] = remote;
      return SyncCoordinatorService(
        accountUserId: accountUserId,
        labelsEnabled: labelsEnabled,
        localStore: localSyncStoreFactory(accountUserId: accountUserId),
        remote: remote,
        clock: _clock,
        requireSession: requireLive,
        observeSnapshot: (snapshot) async {
          await observeSnapshot?.call(accountUserId, snapshot);
        },
        hydrateSnapshot: (snapshot) async {
          await hydrateSnapshot?.call(accountUserId, snapshot);
        },
      );
    });
  }

  /// Starts sync without making local note/auth actions wait for the network.
  void requestSync(String accountUserId) {
    unawaited(_syncBestEffort(accountUserId));
  }

  /// Exposes a manual/run-to-completion path for future sync UI and tests.
  Future<SyncReport> syncNow(String accountUserId) async {
    final report = await coordinatorFor(accountUserId).syncNow();
    requireSession?.call(accountUserId);
    if (labelsEnabled) onCatalogChanged?.call(accountUserId);
    return report;
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
