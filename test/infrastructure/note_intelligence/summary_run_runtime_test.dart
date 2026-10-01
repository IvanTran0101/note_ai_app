import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/note_intelligence/summary_cloud_consent.dart';
import 'package:note_ai_app/application/note_intelligence/summary_run_context.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/local_sync_store.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/note_intelligence/summary.dart';
import 'package:note_ai_app/infrastructure/configuration/summary_runtime_configuration.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_run_runtime.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_request_policy.dart';

import 'summary_policy_test_support.dart' show loadSummaryTestPolicy;
import 'summary_gateway_test_support.dart' show jwt;

final class _Store implements ILocalSyncStore {
  _Store(this.state);
  LocalSyncState state;

  @override
  Future<LocalSyncState> read() async => state;

  @override
  Future<LocalSyncState> update(
    LocalSyncState Function(LocalSyncState current) transform,
  ) async => state = transform(state);

  @override
  Future<void> replace(LocalSyncState value) async => state = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CurrentUserSession session;
  late SummaryCloudConsent consent;
  late _Store store;
  late NoteDto note;
  final DateTime created = DateTime.utc(2026, 10, 1);

  setUp(() {
    session = CurrentUserSession()
      ..setIdentity(
        AuthIdentity(
          userId: 'account-a',
          email: 'a@example.test',
          isEmailVerified: true,
        ),
      );
    consent = SummaryCloudConsent(session: session);
    note = NoteDto(
      id: 'note-1',
      ownerId: 'account-a',
      title: 'Saved title',
      content: 'Saved note body',
      createdAt: created,
      updatedAt: created,
    );
    store = _Store(
      LocalSyncState(
        accountUserId: 'account-a',
        notes: <LocalNoteState>[
          LocalNoteState(
            id: note.id,
            ownerId: note.ownerId,
            title: note.title,
            content: note.content,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
          ),
        ],
      ),
    );
  });

  SummaryRuntimeConfiguration remoteConfig() => SummaryRuntimeConfiguration(
    mode: 'remote',
    explicitEndpoint: 'https://mock.example/prod',
  );

  SummaryRunContext runContext({SummaryRunScope? scope}) => SummaryRunContext(
    noteSnapshot: note,
    accountUserId: 'account-a',
    sessionGeneration: session.sessionGeneration,
    consent: consent.capture(
      accountUserId: 'account-a',
      sessionGeneration: session.sessionGeneration,
    ),
    scope: scope ?? SummaryRunScope(),
  );

  SummaryRunRuntime runtime({
    required MockClient client,
    Future<String?> Function({required bool forceRefresh})? tokenProvider,
    SummaryRuntimeConfiguration? configuration,
    bool cognitoMode = true,
  }) => SummaryRunRuntime(
    configuration: configuration ?? remoteConfig(),
    currentUser: session,
    session: session,
    consent: consent,
    localSyncStoreForAccount: ({required String accountUserId}) => store,
    loadPolicy: loadSummaryTestPolicy,
    tokenProvider:
        tokenProvider ??
        ({required bool forceRefresh}) async => jwt('account-a'),
    cognitoMode: cognitoMode,
    client: client,
  );

  test(
    'remote run sends the selected saved snapshot through the gateway',
    () async {
      consent.grant(
        accountUserId: 'account-a',
        sessionGeneration: session.sessionGeneration,
      );
      final List<http.Request> requests = <http.Request>[];
      final MockClient client = MockClient((http.Request request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, Object?>{
            'summary': 'Saved note summary',
            'requestId': 'synthetic-1',
            'usage': <String, int>{'inputTokens': 100, 'outputTokens': 10},
          }),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      addTearDown(client.close);
      final SummaryRunContext context = runContext();

      final Summary result = await runtime(client: client).summarize(context);

      expect(result, const Summary('Saved note summary'));
      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/prod/ai/summary');
      expect(jsonDecode(requests.single.body), <String, Object?>{
        'stage': 'direct',
        'inputs': <String>['Saved note body'],
        'consent': <String, Object?>{
          'accepted': true,
          'version': 'summary-cloud-v1',
        },
      });
    },
  );

  test('an ungranted snapshot is refused before policy load or HTTP', () async {
    final MockClient client = MockClient(
      (http.Request request) async => throw StateError('must not send'),
    );
    addTearDown(client.close);
    int policyLoads = 0;
    final SummaryRunRuntime instance = SummaryRunRuntime(
      configuration: remoteConfig(),
      currentUser: session,
      session: session,
      consent: consent,
      localSyncStoreForAccount: ({required String accountUserId}) => store,
      loadPolicy: () async {
        policyLoads++;
        return loadSummaryTestPolicy();
      },
      tokenProvider: ({required bool forceRefresh}) async => jwt('account-a'),
      client: client,
    );

    await expectLater(
      instance.summarize(runContext()),
      throwsA(const SummaryRunFailure(SummaryRunFailureCode.consentRequired)),
    );
    expect(policyLoads, 0);
  });

  test('an account switch during token lookup stops before HTTP', () async {
    consent.grant(
      accountUserId: 'account-a',
      sessionGeneration: session.sessionGeneration,
    );
    final Completer<String?> token = Completer<String?>();
    final Completer<void> enteredTokenRead = Completer<void>();
    int sends = 0;
    final MockClient client = MockClient((http.Request request) async {
      sends++;
      return http.Response('', 500);
    });
    addTearDown(client.close);
    final SummaryRunScope scope = SummaryRunScope();
    final Future<Summary> pending = runtime(
      client: client,
      tokenProvider: ({required bool forceRefresh}) {
        enteredTokenRead.complete();
        return token.future;
      },
    ).summarize(runContext(scope: scope));
    await enteredTokenRead.future;

    session.clear();
    session.setIdentity(
      AuthIdentity(
        userId: 'account-a',
        email: 'a@example.test',
        isEmailVerified: true,
      ),
    );
    scope.cancel(reason: SummaryRunFailureCode.sessionChanged);

    await expectLater(
      pending,
      throwsA(const SummaryRunFailure(SummaryRunFailureCode.sessionChanged)),
    );
    token.complete(jwt('account-a'));
    await Future<void>.delayed(Duration.zero);
    expect(sends, 0);
  });

  test(
    'a saved-note change while reading the token sends no stale body',
    () async {
      consent.grant(
        accountUserId: 'account-a',
        sessionGeneration: session.sessionGeneration,
      );
      final Completer<String?> token = Completer<String?>();
      final Completer<void> enteredTokenRead = Completer<void>();
      int sends = 0;
      final MockClient client = MockClient((http.Request request) async {
        sends++;
        return http.Response('', 500);
      });
      addTearDown(client.close);
      final Future<Summary> pending = runtime(
        client: client,
        tokenProvider: ({required bool forceRefresh}) {
          enteredTokenRead.complete();
          return token.future;
        },
      ).summarize(runContext());
      await enteredTokenRead.future;
      store.state = LocalSyncState(
        accountUserId: 'account-a',
        notes: <LocalNoteState>[
          LocalNoteState(
            id: note.id,
            ownerId: note.ownerId,
            title: note.title,
            content: 'A newer body',
            createdAt: note.createdAt,
            updatedAt: created.add(const Duration(minutes: 1)),
          ),
        ],
      );
      token.complete(jwt('account-a'));

      await expectLater(
        pending,
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.noteChanged)),
      );
      expect(sends, 0);
    },
  );

  test('revoking consent while reading the token aborts before HTTP', () async {
    consent.grant(
      accountUserId: 'account-a',
      sessionGeneration: session.sessionGeneration,
    );
    final Completer<String?> token = Completer<String?>();
    final Completer<void> enteredTokenRead = Completer<void>();
    int sends = 0;
    final MockClient client = MockClient((http.Request request) async {
      sends++;
      return http.Response('', 500);
    });
    addTearDown(client.close);
    final SummaryRunScope scope = SummaryRunScope();
    final SummaryRunRuntime runTime = runtime(
      client: client,
      tokenProvider: ({required bool forceRefresh}) {
        enteredTokenRead.complete();
        return token.future;
      },
    );
    final Future<Summary> pending = runTime.summarize(runContext(scope: scope));
    await enteredTokenRead.future;
    runTime.revokeConsent(accountUserId: 'account-a');

    await expectLater(
      pending,
      throwsA(const SummaryRunFailure(SummaryRunFailureCode.consentRequired)),
    );
    token.complete(jwt('account-a'));
    await Future<void>.delayed(Duration.zero);
    expect(sends, 0);
  });

  test('one scope cannot start a second concurrent invocation', () async {
    consent.grant(
      accountUserId: 'account-a',
      sessionGeneration: session.sessionGeneration,
    );
    final Completer<String?> token = Completer<String?>();
    final Completer<void> enteredTokenRead = Completer<void>();
    final MockClient client = MockClient((http.Request request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'summary': 'Done',
          'requestId': 'synthetic-1',
          'usage': <String, int>{'inputTokens': 10, 'outputTokens': 2},
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);
    final SummaryRunRuntime instance = runtime(
      client: client,
      tokenProvider: ({required bool forceRefresh}) {
        enteredTokenRead.complete();
        return token.future;
      },
    );
    final SummaryRunContext context = runContext();
    final Future<Summary> first = instance.summarize(context);
    await enteredTokenRead.future;

    await expectLater(
      instance.summarize(context),
      throwsA(const SummaryRunFailure(SummaryRunFailureCode.alreadyRunning)),
    );
    token.complete(jwt('account-a'));
    expect(await first, const Summary('Done'));
  });

  test('cancelling a stalled policy load ends the run without HTTP', () async {
    consent.grant(
      accountUserId: 'account-a',
      sessionGeneration: session.sessionGeneration,
    );
    final Completer<SummaryRequestPolicy> policy =
        Completer<SummaryRequestPolicy>();
    final Completer<void> enteredPolicyLoad = Completer<void>();
    int sends = 0;
    final MockClient client = MockClient((http.Request request) async {
      sends++;
      return http.Response('', 500);
    });
    addTearDown(client.close);
    final SummaryRunScope scope = SummaryRunScope();
    final SummaryRunRuntime instance = SummaryRunRuntime(
      configuration: remoteConfig(),
      currentUser: session,
      session: session,
      consent: consent,
      localSyncStoreForAccount: ({required String accountUserId}) => store,
      loadPolicy: () {
        enteredPolicyLoad.complete();
        return policy.future;
      },
      tokenProvider: ({required bool forceRefresh}) async => jwt('account-a'),
      client: client,
    );
    final Future<Summary> pending = instance.summarize(
      runContext(scope: scope),
    );
    await enteredPolicyLoad.future;
    scope.cancel();

    await expectLater(
      pending,
      throwsA(const SummaryRunFailure(SummaryRunFailureCode.cancelled)),
    );
    policy.complete(loadSummaryTestPolicy());
    await Future<void>.delayed(Duration.zero);
    expect(sends, 0);
  });

  test('a rejected policy load can be retried by a fresh scope', () async {
    consent.grant(
      accountUserId: 'account-a',
      sessionGeneration: session.sessionGeneration,
    );
    int loads = 0;
    final MockClient client = MockClient((http.Request request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'summary': 'Retry worked',
          'requestId': 'synthetic-1',
          'usage': <String, int>{'inputTokens': 10, 'outputTokens': 2},
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);
    final SummaryRunRuntime instance = SummaryRunRuntime(
      configuration: remoteConfig(),
      currentUser: session,
      session: session,
      consent: consent,
      localSyncStoreForAccount: ({required String accountUserId}) => store,
      loadPolicy: () async {
        if (++loads == 1) throw StateError('synthetic policy error');
        return loadSummaryTestPolicy();
      },
      tokenProvider: ({required bool forceRefresh}) async => jwt('account-a'),
      client: client,
    );

    await expectLater(instance.summarize(runContext()), throwsStateError);
    expect(
      await instance.summarize(runContext()),
      const Summary('Retry worked'),
    );
    expect(loads, 2);
  });

  test('unknown configuration and non-Cognito mode fail before HTTP', () async {
    int sends = 0;
    final MockClient client = MockClient((http.Request request) async {
      sends++;
      return http.Response('', 500);
    });
    addTearDown(client.close);
    final SummaryRuntimeConfiguration unavailable = SummaryRuntimeConfiguration(
      mode: 'typo',
    );

    await expectLater(
      runtime(
        client: client,
        configuration: unavailable,
      ).summarize(runContext()),
      throwsA(
        const SummaryRunFailure(SummaryRunFailureCode.runtimeUnavailable),
      ),
    );
    await expectLater(
      runtime(client: client, cognitoMode: false).summarize(runContext()),
      throwsA(
        const SummaryRunFailure(SummaryRunFailureCode.runtimeUnavailable),
      ),
    );
    expect(sends, 0);
  });
}
