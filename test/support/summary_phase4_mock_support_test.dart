import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/note_intelligence/summary_run_context.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/domain/note_intelligence/summary.dart';

import '../infrastructure/note_intelligence/summary_policy_test_support.dart';
import 'summary_phase4_mock_support.dart';

/// The exact `NoteDto` the mock store persists, so the run guard passes.
NoteDto _snapshotOf(SummaryMockSyncStore store) {
  final LocalNoteState note = store.state.notes.first;
  return NoteDto(
    id: note.id,
    ownerId: note.ownerId,
    title: note.title,
    content: note.content,
    createdAt: note.createdAt,
    updatedAt: note.updatedAt,
  );
}

/// Grants consent, then runs one summary through the real runtime and guard.
Future<Summary> _runOnce(
  SummaryMockEnvironment environment,
  SummaryRunScope scope,
) {
  final String account = environment.session.requiredUserId;
  final int generation = environment.session.sessionGeneration;
  environment.runtime.consent.grant(
    accountUserId: account,
    sessionGeneration: generation,
  );
  return environment.runtime.summarize(
    SummaryRunContext(
      noteSnapshot: _snapshotOf(environment.activeStore),
      accountUserId: account,
      sessionGeneration: generation,
      consent: environment.runtime.consent.capture(
        accountUserId: account,
        sessionGeneration: generation,
      ),
      scope: scope,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the mock store seeds exactly one saved note for its account', () async {
    final SummaryMockEnvironment environment = createSummaryMockEnvironment(
      loadPolicy: loadSummaryTestPolicy,
    );
    addTearDown(environment.dispose);

    final SummaryMockSyncStore store = environment.activeStore;
    expect(store.accountUserId, summaryMockAccountId);
    expect(store.state.notes, hasLength(1));
    expect(store.state.notes.single.ownerId, summaryMockAccountId);
    expect(store.state.notes.single.content, summaryMockNoteContent);
    expect(store.state.conflicts, isEmpty);
    expect(store.readCount, 0);
    await store.read();
    expect(store.readCount, 1);
  });

  test(
    'the runtime serves the frozen success envelope for a direct run',
    () async {
      final SummaryMockEnvironment environment = createSummaryMockEnvironment(
        loadPolicy: loadSummaryTestPolicy,
      );
      addTearDown(environment.dispose);

      final SummaryRunScope scope = SummaryRunScope();
      final Summary summary = await _runOnce(environment, scope);
      scope.release();

      expect(summary.text, summaryMockText('direct', 1));
      expect(environment.control.requestCount.value, 1);
      expect(environment.control.policyLoaded.value, isTrue);
      expect(environment.control.policySource.value, 'injected');
      final SummaryMockRequest request = environment.client.requests.single;
      expect(request.stage, 'direct');
      expect(request.inputs.single, summaryMockNoteContent);
      expect(request.consentAccepted, isTrue);
      expect(request.consentVersion, isNotEmpty);
      expect(environment.client.hasPendingCall, isFalse);
    },
  );

  test('the JWT the mock serves carries the account the gateway expects', () {
    final String token = summaryMockJwt('account-mock-1');
    expect(token.split('.'), hasLength(3));
    expect(
      summaryMockJwt('a', id: 'one'),
      isNot(summaryMockJwt('a', id: 'two')),
    );
  });

  test('every failure mode maps to its own typed run failure', () async {
    final SummaryMockEnvironment environment = createSummaryMockEnvironment(
      loadPolicy: loadSummaryTestPolicy,
    );
    addTearDown(environment.dispose);

    const Map<SummaryMockMode, SummaryRunFailureCode> expected =
        <SummaryMockMode, SummaryRunFailureCode>{
          SummaryMockMode.providerUnavailable:
              SummaryRunFailureCode.serviceUnavailable,
          SummaryMockMode.invalidOutput: SummaryRunFailureCode.invalidOutput,
          SummaryMockMode.unauthorized: SummaryRunFailureCode.unauthorized,
          SummaryMockMode.rateLimited: SummaryRunFailureCode.rateLimited,
        };

    for (final MapEntry<SummaryMockMode, SummaryRunFailureCode> entry
        in expected.entries) {
      environment.control.mode.value = entry.key;
      final SummaryRunScope scope = SummaryRunScope();
      await expectLater(
        _runOnce(environment, scope),
        throwsA(
          isA<SummaryRunFailure>().having(
            (SummaryRunFailure failure) => failure.code,
            'code',
            entry.value,
          ),
        ),
        reason: 'mode ${entry.key.label}',
      );
      scope.release();
    }
    // The unauthorized case includes the one allowed token-refresh HTTP retry.
    expect(environment.control.requestCount.value, expected.length + 1);
  });

  test('a cancelled delayed call aborts the held request', () async {
    final SummaryMockEnvironment environment = createSummaryMockEnvironment(
      loadPolicy: loadSummaryTestPolicy,
      delay: const Duration(seconds: 30),
    );
    addTearDown(environment.dispose);
    environment.control.mode.value = SummaryMockMode.delayed;

    final SummaryRunScope scope = SummaryRunScope();
    final Future<Summary> pending = _runOnce(environment, scope);
    // Let the runtime reach the transport before the user cancels.
    await Future<void>.delayed(Duration.zero);
    expect(environment.client.hasPendingCall, isTrue);

    scope.cancel();
    await expectLater(
      pending,
      throwsA(
        isA<SummaryRunFailure>().having(
          (SummaryRunFailure failure) => failure.code,
          'code',
          SummaryRunFailureCode.cancelled,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(environment.client.hasPendingCall, isFalse);
    expect(environment.client.requests, hasLength(1));
  });

  test('releasing a held call answers the waiting run', () async {
    final SummaryMockEnvironment environment = createSummaryMockEnvironment(
      loadPolicy: loadSummaryTestPolicy,
      delay: const Duration(seconds: 30),
    );
    addTearDown(environment.dispose);
    environment.control.mode.value = SummaryMockMode.delayed;

    final SummaryRunScope scope = SummaryRunScope();
    final Future<Summary> pending = _runOnce(environment, scope);
    await Future<void>.delayed(Duration.zero);
    environment.client.releaseHeld();

    expect((await pending).text, summaryMockText('direct', 1));
    expect(environment.client.hasPendingCall, isFalse);
    scope.release();
  });
}
