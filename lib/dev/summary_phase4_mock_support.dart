/// Offline mock environment for the Phase 4.5 Summary acceptance work.
///
/// This is the composition entry point: it wires the session, the mock auth
/// service, the in-memory store registry, the mock transport, and the
/// `SummaryRunRuntime` the production root app dispatches through. It re-exports
/// the transport and storage doubles, so importing this one library is enough.
///
/// It must never import `package:flutter_test/flutter_test.dart`: the offline
/// tool entrypoint (`tool/summary_phase4_mock.dart`) runs as a real Flutter app.
/// Everything here is in-memory — no Amplify, no Cognito, no asset read, no
/// persistence, no credential, and no real I/O.
library;

import 'package:note_ai_app/application/auth/auth_models.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/note_intelligence/summary_cloud_consent.dart';
import 'package:note_ai_app/infrastructure/configuration/summary_runtime_configuration.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_request_policy.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_run_runtime.dart';
import 'package:note_ai_app/presentation/auth/controllers/auth_controller.dart';

import 'summary_phase4_mock_storage.dart';
import 'summary_phase4_mock_transport.dart';

export 'summary_phase4_mock_storage.dart';
export 'summary_phase4_mock_transport.dart';

/// Everything one offline Summary run needs, wired without any provider.
final class SummaryMockEnvironment {
  /// Creates the bundle; build it through [createSummaryMockEnvironment].
  SummaryMockEnvironment({
    required this.session,
    required this.auth,
    required this.control,
    required this.client,
    required this.runtime,
    required this.authController,
    required this.seedNoteId,
    required this.stores,
  });

  /// The live application session.
  final CurrentUserSession session;

  /// The provider-neutral auth fake.
  final SummaryMockAuth auth;

  /// Observable smoke state.
  final SummaryMockControl control;

  /// The local Summary transport.
  final SummaryMockHttpClient client;

  /// The remote Summary runtime the app will dispatch through.
  final SummaryRunRuntime runtime;

  /// The auth controller the root app renders with.
  final AuthController authController;

  /// Id of the synthetic note every account store is seeded with.
  final String seedNoteId;

  /// The account-keyed store registry shared with the runtime guard.
  final SummaryMockStoreRegistry stores;

  /// Returns the account store, seeding it with one synthetic note.
  SummaryMockSyncStore storeFor({required String accountUserId}) =>
      stores.storeFor(accountUserId: accountUserId);

  /// The store of the account that is signed in right now.
  SummaryMockSyncStore get activeStore =>
      storeFor(accountUserId: session.requiredUserId);

  /// The `summary` text served by the last success envelope.
  String? get lastSummary => client.lastSummary;

  /// Releases the transport and cancels any active run.
  ///
  /// The [authController] is owned by the root app, which disposes it with the
  /// widget tree, so it is deliberately left alone here.
  void dispose() {
    runtime.dispose();
    client.close();
    auth.dispose();
  }
}

/// Wires one complete offline Summary environment.
///
/// [loadPolicy] defaults to the shipped asset loader ([SummaryRequestPolicy]).
/// Chrome's `flutter test` harness cannot read bundled assets, so widget tests
/// pass the existing `loadSummaryTestPolicy` helper instead, which is disclosed
/// in the test that relies on it. [delay] only affects
/// [SummaryMockMode.delayed]. [localRuntime] selects the on-device runtime
/// instead of the mocked remote one, for the native latch smoke run.
SummaryMockEnvironment createSummaryMockEnvironment({
  String accountUserId = summaryMockAccountId,
  String email = 'mock@noteflow.local',
  String noteId = summaryMockNoteId,
  SummaryPolicyLoader? loadPolicy,
  Duration delay = const Duration(seconds: 30),
  bool signedIn = true,
  bool localRuntime = false,
}) {
  final CurrentUserSession session = CurrentUserSession();
  final SummaryMockAuth auth = SummaryMockAuth(
    session: session,
    accountUserId: accountUserId,
    email: email,
  );
  if (signedIn) {
    session.setIdentity(auth.identity);
  }
  final SummaryMockControl control = SummaryMockControl(
    policySource: loadPolicy == null ? 'bundled' : 'injected',
  );
  final SummaryMockHttpClient client = SummaryMockHttpClient(
    control: control,
    delay: delay,
  );
  final SummaryMockStoreRegistry stores = SummaryMockStoreRegistry();
  final SummaryMockEnvironment environment = SummaryMockEnvironment(
    session: session,
    auth: auth,
    control: control,
    client: client,
    runtime: localRuntime
        ? _buildLocalRuntime(
            session: session,
            control: control,
            stores: stores,
            loadPolicy: loadPolicy,
          )
        : _buildRuntime(
            session: session,
            control: control,
            client: client,
            stores: stores,
            loadPolicy: loadPolicy,
          ),
    authController: AuthController(
      authenticationAppService: auth,
      initialUser: signedIn ? AuthUserDto.fromIdentity(auth.identity) : null,
    ),
    seedNoteId: noteId,
    stores: stores,
  );
  environment.storeFor(accountUserId: accountUserId);
  return environment;
}

/// Builds the remote-mode runtime over the local mock transport.
///
/// The base URI is a reserved, unresolvable host, so even a misrouted client
/// could not reach a deployment; the injected mock answers every request.
SummaryRunRuntime _buildRuntime({
  required CurrentUserSession session,
  required SummaryMockControl control,
  required SummaryMockHttpClient client,
  required SummaryMockStoreRegistry stores,
  required SummaryPolicyLoader? loadPolicy,
}) {
  return SummaryRunRuntime(
    configuration: SummaryRuntimeConfiguration(
      mode: SummaryRuntimeConfiguration.remoteModeToken,
      explicitEndpoint: 'https://summary-mock.invalid',
    ),
    session: session,
    currentUser: session,
    consent: SummaryCloudConsent(session: session),
    localSyncStoreForAccount: stores.storeFor,
    loadPolicy: () async {
      final SummaryRequestPolicy policy =
          await (loadPolicy ?? SummaryRequestPolicy.load)();
      control.policyLoaded.value = true;
      return policy;
    },
    tokenProvider: ({required bool forceRefresh}) async => summaryMockJwt(
      session.userId ?? summaryMockAccountId,
      id: forceRefresh ? 'refresh' : 'initial',
    ),
    client: client,
  );
}

/// Builds the on-device runtime for the native latch smoke run.
///
/// The local runtime never dispatches a Summary HTTP call, so no policy or
/// token is ever read here; both seams are wired only to satisfy the runtime's
/// constructor.
SummaryRunRuntime _buildLocalRuntime({
  required CurrentUserSession session,
  required SummaryMockControl control,
  required SummaryMockStoreRegistry stores,
  required SummaryPolicyLoader? loadPolicy,
}) {
  return SummaryRunRuntime(
    configuration: SummaryRuntimeConfiguration(),
    session: session,
    currentUser: session,
    consent: SummaryCloudConsent(session: session),
    localSyncStoreForAccount: stores.storeFor,
    loadPolicy: () async {
      final SummaryRequestPolicy policy =
          await (loadPolicy ?? SummaryRequestPolicy.load)();
      control.policyLoaded.value = true;
      return policy;
    },
    tokenProvider: ({required bool forceRefresh}) async => null,
    cognitoMode: false,
  );
}
