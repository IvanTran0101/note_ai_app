import '../../application/notes/note_access.dart';
import 'summary_note_lineage.dart';

import 'package:http/http.dart' as http;

import '../../application/auth/current_user.dart';
import '../../application/auth/current_user_session.dart';
import '../../application/note_intelligence/summary_cloud_consent.dart';
import '../../application/note_intelligence/summary_run_context.dart';
import '../../application/note_intelligence/summary_run_guard.dart';
import '../../application/notes/note_application.dart';
import '../../application/sync/local_sync_store.dart';
import '../../domain/note_intelligence/summary.dart';
import '../sync/cognito_access_token_provider.dart';
import '../configuration/summary_runtime_configuration.dart';
import 'remote_summarization_service.dart';
import 'summary_failure_mapper.dart';
import 'summary_http_gateway.dart';
import 'summary_request_policy.dart';

typedef SummaryPolicyLoader = Future<SummaryRequestPolicy> Function();

/// Owns the remote Summary adapter, account/session gate, and HTTP lifecycle.
///
/// It retains only active cancellation scopes, never a note or run context.
final class SummaryRunRuntime {
  SummaryRunRuntime({
    required this.configuration,
    required this.session,
    required this.currentUser,
    required this.consent,
    required this.localSyncStoreForAccount,
    required this.loadPolicy,
    required this.tokenProvider,
    this.accessGuardForAccount,
    this.grantHeaderForRun,
    this.cognitoMode = true,
    this.client,
  }) : _guard = SummaryRunGuard(
         accessGuardForAccount: accessGuardForAccount,
         currentUser: currentUser,
         session: session,
         consent: consent,
         localSyncStoreForAccount: localSyncStoreForAccount,
       );

  factory SummaryRunRuntime.fromEnvironment({
    required CurrentUserSession session,
    required ILocalSyncStore Function({required String accountUserId})
    localSyncStoreForAccount,
    required String amplifyOutputsJson,
    INoteAccessGuard Function(String accountId)? accessGuardForAccount,
    String? Function(SummaryRunContext context)? grantHeaderForRun,
    bool cognitoMode = true,
    http.Client? client,
  }) => SummaryRunRuntime(
    configuration: SummaryRuntimeConfiguration.fromEnvironment(
      amplifyOutputsJson: amplifyOutputsJson,
    ),
    session: session,
    currentUser: session,
    consent: SummaryCloudConsent(session: session),
    localSyncStoreForAccount: localSyncStoreForAccount,
    loadPolicy: SummaryRequestPolicy.load,
    tokenProvider: const CognitoAccessTokenProvider().call,
    accessGuardForAccount: accessGuardForAccount,
    grantHeaderForRun: grantHeaderForRun,
    cognitoMode: cognitoMode,
    client: client,
  );

  final SummaryRuntimeConfiguration configuration;
  final SessionGenerationSource session;
  final ICurrentUser currentUser;
  final SummaryCloudConsent consent;
  final ILocalSyncStore Function({required String accountUserId})
  localSyncStoreForAccount;
  final SummaryPolicyLoader loadPolicy;
  final Future<String?> Function({required bool forceRefresh}) tokenProvider;
  final bool cognitoMode;
  final INoteAccessGuard Function(String accountId)? accessGuardForAccount;
  final String? Function(SummaryRunContext context)? grantHeaderForRun;

  /// A borrowed HTTP client remains owned by the caller.
  final http.Client? client;

  final SummaryRunGuard _guard;
  final Set<SummaryRunScope> _scopes = <SummaryRunScope>{};
  Future<SummaryRequestPolicy>? _policy;
  http.Client? _ownedClient;

  /// True when a remote summary callback should be wired into Application.
  bool get dispatchesSummary => configuration.mode != SummaryRuntimeMode.local;

  /// Runs one remote summary for a validated saved-note snapshot.
  Future<Summary> summarize(SummaryRunContext context) async {
    if (!configuration.canSummarize ||
        !configuration.isRemote ||
        !cognitoMode) {
      throw const SummaryRunFailure(SummaryRunFailureCode.runtimeUnavailable);
    }
    _scopes.removeWhere(
      (SummaryRunScope scope) => scope.isCancelled || scope.isReleased,
    );
    if (_scopes.isNotEmpty) {
      throw const SummaryRunFailure(SummaryRunFailureCode.alreadyRunning);
    }
    _scopes.add(context.scope);

    try {
      return await Future.any<Summary>(<Future<Summary>>[
        _run(context),
        context.scope.whenCancelled.then<Summary>((_) {
          throw SummaryRunFailure(
            context.scope.cancelReason ?? SummaryRunFailureCode.cancelled,
          );
        }),
      ]);
    } finally {
      _scopes.remove(context.scope);
    }
  }

  /// Runs the remote pipeline behind [withSummaryFailureBoundary].
  ///
  /// Known failures keep their code and instance; a policy load, local store
  /// read, transport, or service failure that is not classified becomes
  /// [SummaryRunFailureCode.unexpected], so no Infrastructure exception ever
  /// reaches the caller. Cancellation stays outside this boundary: the scope
  /// race in [summarize] and the scope cleanup in its `finally` are unchanged.
  Future<Summary> _run(SummaryRunContext context) =>
      withSummaryFailureBoundary<Summary>(() async {
        await _guard.revalidate(context, requireConsent: true);
        final SummaryRequestPolicy policy;
        try {
          policy = await (_policy ??= loadPolicy());
        } catch (_) {
          _policy = null;
          rethrow;
        }
        await _guard.revalidate(context, requireConsent: true);

        final SummaryHttpGateway gateway = SummaryHttpGateway(
          baseUri: configuration.endpoint!,
          policy: policy,
          tokenProvider: tokenProvider,
          expectedAccountUserId: context.accountUserId,
          runScope: context.scope,
          noteLineage: SummaryNoteLineage(context),
          grantHeader: () => grantHeaderForRun?.call(context),
          beforeDispatch: () =>
              _guard.revalidate(context, requireConsent: true),
          currentRunFailure: () =>
              _guard.currentFailure(context, requireConsent: true),
          client: _httpClient,
        );
        final RemoteSummarizationService service = RemoteSummarizationService(
          policy: policy,
          generate: gateway.generate,
          hasConsent: () => consent.isCurrent(context.consent),
        );
        final Summary result = await service.summarize(
          context.noteSnapshot.content,
        );
        await _guard.revalidate(context, requireConsent: true);
        return result;
      });

  /// Cancels all active runs on sign-out, account change, or app shutdown.
  void cancelActive({
    SummaryRunFailureCode reason = SummaryRunFailureCode.sessionChanged,
  }) {
    for (final SummaryRunScope scope in _scopes) {
      scope.cancel(reason: reason);
    }
    _scopes.removeWhere((SummaryRunScope scope) => scope.isCancelled);
  }

  /// Revokes consent and aborts any HTTP request that belongs to the old grant.
  void revokeConsent({String? accountUserId}) {
    consent.revoke(accountUserId: accountUserId);
    for (final SummaryRunScope scope in _scopes) {
      scope.cancel(reason: SummaryRunFailureCode.consentRequired);
    }
    _scopes.removeWhere((SummaryRunScope scope) => scope.isCancelled);
  }

  void dispose() {
    cancelActive();
    _ownedClient?.close();
    _ownedClient = null;
  }

  http.Client get _httpClient {
    final http.Client? borrowed = client;
    if (borrowed != null) return borrowed;
    return _ownedClient ??= http.Client();
  }
}
