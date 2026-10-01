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
import 'package:note_ai_app/infrastructure/note_intelligence/summary_api_failure.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_request_policy.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_run_runtime.dart';

import 'summary_gateway_test_support.dart' show jwt, successBody;
import 'summary_policy_test_support.dart' show loadSummaryTestPolicy;

final class _Store implements ILocalSyncStore {
  _Store(this.state);

  LocalSyncState state;
  Object? readError;

  @override
  Future<LocalSyncState> read() async {
    final Object? error = readError;
    if (error != null) {
      throw error;
    }
    return state;
  }

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
  final List<MockClient> clients = <MockClient>[];

  setUp(() {
    session = CurrentUserSession()
      ..setIdentity(
        AuthIdentity(
          userId: 'account-a',
          email: 'a@example.test',
          isEmailVerified: true,
        ),
      );
    consent = SummaryCloudConsent(session: session)
      ..grant(
        accountUserId: 'account-a',
        sessionGeneration: session.sessionGeneration,
      );
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

  tearDown(() {
    for (final MockClient client in clients) {
      client.close();
    }
    clients.clear();
  });

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

  SummaryRunRuntime runtimeFor({
    required MockClient client,
    Future<SummaryRequestPolicy> Function()? loadPolicy,
    Future<String?> Function({required bool forceRefresh})? tokenProvider,
  }) => SummaryRunRuntime(
    configuration: SummaryRuntimeConfiguration(
      mode: 'remote',
      explicitEndpoint: 'https://mock.example/prod',
    ),
    currentUser: session,
    session: session,
    consent: consent,
    localSyncStoreForAccount: ({required String accountUserId}) => store,
    loadPolicy: loadPolicy ?? loadSummaryTestPolicy,
    tokenProvider:
        tokenProvider ??
        ({required bool forceRefresh}) async => jwt('account-a'),
    client: client,
  );

  MockClient respondingWith(
    int status,
    String body, {
    Map<String, String> headers = const <String, String>{},
  }) {
    final MockClient client = MockClient(
      (http.Request request) async => http.Response(
        body,
        status,
        headers: <String, String>{
          'content-type': 'application/json; charset=utf-8',
          ...headers,
        },
      ),
    );
    clients.add(client);
    return client;
  }

  String envelope(SummaryApiErrorCode code) => jsonEncode(<String, Object?>{
    'error': <String, Object?>{'code': code.name},
    'requestId': 'req-1',
  });

  Future<SummaryRunFailure> failureOf(Future<void> run) async {
    try {
      await run;
    } on Object catch (error) {
      expect(
        error,
        isA<SummaryRunFailure>(),
        reason: 'only a safe application failure may leave the runtime',
      );
      return error as SummaryRunFailure;
    }
    fail('the run must fail instead of returning a summary');
  }

  test('a real 429 reaches the caller with its retry hint', () async {
    final SummaryRunFailure failure = await failureOf(
      runtimeFor(
        client: respondingWith(
          429,
          envelope(SummaryApiErrorCode.rateLimited),
          headers: <String, String>{'retry-after': '120'},
        ),
      ).summarize(runContext()),
    );

    expect(failure.code, SummaryRunFailureCode.rateLimited);
    expect(failure.retryAfterSeconds, 120);
    expect(
      failure,
      const SummaryRunFailure(
        SummaryRunFailureCode.rateLimited,
        retryAfterSeconds: 120,
      ),
    );
  });

  test('an unusable retry hint is dropped, not guessed', () async {
    final SummaryRunFailure failure = await failureOf(
      runtimeFor(
        client: respondingWith(
          429,
          envelope(SummaryApiErrorCode.rateLimited),
          headers: <String, String>{
            'retry-after': 'Wed, 21 Oct 2026 07:28:00 GMT',
          },
        ),
      ).summarize(runContext()),
    );

    expect(failure.code, SummaryRunFailureCode.rateLimited);
    expect(failure.retryAfterSeconds, isNull);
  });

  test('a provider outage becomes serviceUnavailable', () async {
    final SummaryRunFailure failure = await failureOf(
      // 502 is the contract's provider-unavailable status; 503 is not in its
      // table, so that status fails closed as unexpected (asserted below).
      runtimeFor(
        client: respondingWith(
          502,
          envelope(SummaryApiErrorCode.providerUnavailable),
        ),
      ).summarize(runContext()),
    );

    expect(failure.code, SummaryRunFailureCode.serviceUnavailable);
  });

  test('a status outside the contract fails closed as unexpected', () async {
    final SummaryRunFailure failure = await failureOf(
      runtimeFor(
        client: respondingWith(
          503,
          envelope(SummaryApiErrorCode.providerUnavailable),
        ),
      ).summarize(runContext()),
    );

    expect(failure.code, SummaryRunFailureCode.unexpected);
  });

  test('a malformed success becomes invalidOutput', () async {
    final SummaryRunFailure failure = await failureOf(
      runtimeFor(
        client: respondingWith(
          200,
          jsonEncode(<String, Object?>{
            'summary': 'text without the rest of the envelope',
          }),
        ),
      ).summarize(runContext()),
    );

    expect(failure.code, SummaryRunFailureCode.invalidOutput);
  });

  test('a policy load error becomes unexpected and stays retryable', () async {
    const String canary = 'canary-policy-error';
    int loads = 0;
    final SummaryRunRuntime instance = runtimeFor(
      client: respondingWith(200, successBody(summary: 'Retry worked')),
      loadPolicy: () async {
        if (++loads == 1) {
          throw StateError(canary);
        }
        return loadSummaryTestPolicy();
      },
    );

    final SummaryRunFailure first = await failureOf(
      instance.summarize(runContext()),
    );

    expect(first.code, SummaryRunFailureCode.unexpected);
    expect(first.toString(), isNot(contains(canary)));
    expect(
      await instance.summarize(runContext()),
      const Summary('Retry worked'),
    );
    expect(loads, 2);
  });

  test('a local store read error becomes unexpected', () async {
    store.readError = StateError('canary-store-error');

    final SummaryRunFailure failure = await failureOf(
      runtimeFor(client: respondingWith(200, successBody()))
          .summarize(runContext()),
    );

    expect(failure.code, SummaryRunFailureCode.unexpected);
    expect(failure.toString(), 'SummaryRunFailure(unexpected)');
  });

  test('cancellation keeps its original reason and sends nothing', () async {
    final Completer<String?> token = Completer<String?>();
    final Completer<void> enteredTokenRead = Completer<void>();
    int sends = 0;
    final MockClient client = MockClient((http.Request request) async {
      sends++;
      return http.Response(successBody(), 200);
    });
    clients.add(client);
    final SummaryRunScope scope = SummaryRunScope();
    final Future<Summary> pending = runtimeFor(
      client: client,
      tokenProvider: ({required bool forceRefresh}) {
        enteredTokenRead.complete();
        return token.future;
      },
    ).summarize(runContext(scope: scope));
    await enteredTokenRead.future;

    scope.cancel(reason: SummaryRunFailureCode.conflict);

    final SummaryRunFailure failure = await failureOf(pending);
    expect(failure.code, SummaryRunFailureCode.conflict);
    token.complete(jwt('account-a'));
    await Future<void>.delayed(Duration.zero);
    expect(sends, 0);
  });
}
