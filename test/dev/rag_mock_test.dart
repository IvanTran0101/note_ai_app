/// End-to-end tests for the explicit offline RAG mock runtime.
///
/// Every test drives the real `RagHttpGateway` (and, in one test, the real
/// `RagAppService`) over the in-process `RagMockClient`; the widget test pumps
/// the explicit debug mock root and asserts the local-summary refusal it
/// injects into `NoteFlowApp`. Nothing here reaches a network, a model, or a
/// real account; the fixture is the same synthetic note the mock root seeds.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/note_intelligence/rag_app_service.dart';
import 'package:note_ai_app/application/note_intelligence/summary_run_context.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/dev/rag_mock_actors.dart';
import 'package:note_ai_app/dev/rag_mock_client.dart';
import 'package:note_ai_app/dev/rag_mock_fixture.dart';
import 'package:note_ai_app/dev/rag_mock_runtime.dart';
import 'package:note_ai_app/dev/rag_mock_store.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/rag_http_gateway.dart';
import 'package:note_ai_app/main.dart' show NoteFlowApp;
import 'package:note_ai_app/main_rag_mock.dart' as rag_mock;

RagCallContext _context(String actorId) => RagCallContext(
  expectedUserId: actorId,
  cancelled: Completer<void>().future,
  beforeDispatch: () async {},
  deadline: DateTime.now().add(RagCallContext.requestBudget),
);

RagHttpGateway _gateway(RagMockClient client, RagMockActor Function() actor) =>
    RagHttpGateway(
      baseUri: ragMockLogicalBase,
      tokenProvider: ({required bool forceRefresh}) async =>
          ragMockAccessToken(actor()),
      client: client,
    );

Matcher _throwsRag(RagFailureCode code) => throwsA(
  isA<RagFailure>().having((RagFailure failure) => failure.code, 'code', code),
);

String _bearer(RagMockActor actor) => 'Bearer ${ragMockAccessToken(actor)}';

void main() {
  test('guard refuses release and non-loopback Web, allows debug native', () {
    expect(
      ragMockGuardProblem(
        isDebugMode: false,
        isWeb: false,
        baseUri: Uri.parse('https://rag-mock.invalid'),
      ),
      isNotNull,
    );
    expect(
      ragMockGuardProblem(
        isDebugMode: true,
        isWeb: true,
        baseUri: Uri.parse('https://example.com'),
      ),
      isNotNull,
    );
    expect(
      ragMockGuardProblem(
        isDebugMode: true,
        isWeb: true,
        baseUri: Uri.parse('http://127.0.0.1:8783'),
      ),
      isNull,
    );
    expect(
      ragMockGuardProblem(
        isDebugMode: true,
        isWeb: false,
        baseUri: Uri.parse('file:///tmp/app'),
      ),
      isNull,
    );
    expect(
      () => requireRagMockRuntime(
        isDebugMode: false,
        isWeb: false,
        baseUri: Uri.parse('https://rag-mock.invalid'),
      ),
      throwsStateError,
    );
  });

  test(
    'default consent is off and generation compare-and-set is enforced',
    () async {
      final RagMockClient client = RagMockClient();
      final RagHttpGateway gateway = _gateway(client, () => ragMockOwner);

      final RagConsent initial = await gateway.readConsent(
        context: _context(ragMockOwner.userId),
      );
      expect(initial, RagConsent.none);
      expect(initial.accepted, isFalse);
      expect(initial.generation, 0);

      final RagConsent granted = await gateway.updateConsent(
        RagConsentUpdate(accepted: true, expectedGeneration: 0),
        context: _context(ragMockOwner.userId),
      );
      expect(granted.accepted, isTrue);
      expect(granted.generation, 1);

      await expectLater(
        gateway.updateConsent(
          RagConsentUpdate(accepted: false, expectedGeneration: 0),
          context: _context(ragMockOwner.userId),
        ),
        _throwsRag(RagFailureCode.sourceChanged),
      );
      await gateway.close();
    },
  );

  test(
    'answered query carries the exact fixture UTF-16 citation span',
    () async {
      final RagMockClient client = RagMockClient();
      final RagHttpGateway gateway = _gateway(client, () => ragMockOwner);
      final RagMockFixture fixture = ragMockFixtureFor(ragMockOwner);
      await gateway.updateConsent(
        RagConsentUpdate(accepted: true, expectedGeneration: 0),
        context: _context(ragMockOwner.userId),
      );

      final RagResult result = await gateway.query(
        RagRequest(
          question: ragMockAnswerableQuestion,
          scope: const RagScope.account(),
        ),
        context: _context(ragMockOwner.userId),
      );

      expect(result.isAnswered, isTrue);
      final RagSource source = result.sources.single;
      expect(source.noteId, fixture.noteId);
      expect(source.revision, fixture.serverRevision);
      expect(source.quote, fixture.quote);
      expect(source.startOffset, fixture.startOffset);
      expect(source.endOffset, fixture.endOffset);
      expect(source.matchesContent(fixture.content), isTrue);
      expect(
        fixture.content.substring(source.startOffset, source.endOffset),
        fixture.quote,
      );
      await gateway.close();
    },
  );

  test(
    'unrelated and arbitrary questions abstain instead of echoing',
    () async {
      final RagMockClient client = RagMockClient();
      final RagHttpGateway gateway = _gateway(client, () => ragMockOwner);
      await gateway.updateConsent(
        RagConsentUpdate(accepted: true, expectedGeneration: 0),
        context: _context(ragMockOwner.userId),
      );

      for (final String question in <String>[
        ragMockUnrelatedQuestion,
        'Explain quantum gravity.',
      ]) {
        final RagResult result = await gateway.query(
          RagRequest(question: question, scope: const RagScope.account()),
          context: _context(ragMockOwner.userId),
        );
        expect(result.status, RagResultStatus.notEnoughContext);
        expect(result.reason, RagResult.reasonInsufficientEvidence);
        expect(result.sources, isEmpty);
      }
      await gateway.close();
    },
  );

  test('actors have isolated consent and note scopes', () async {
    final RagMockClient client = RagMockClient();
    RagMockActor tokenActor = ragMockOwner;
    final RagHttpGateway gateway = _gateway(client, () => tokenActor);
    final RagMockFixture ownerFixture = ragMockFixtureFor(ragMockOwner);
    final RagMockFixture otherFixture = ragMockFixtureFor(ragMockOther);

    await gateway.updateConsent(
      RagConsentUpdate(accepted: true, expectedGeneration: 0),
      context: _context(ragMockOwner.userId),
    );
    tokenActor = ragMockOther;
    final RagConsent otherInitial = await gateway.readConsent(
      context: _context(ragMockOther.userId),
    );
    expect(otherInitial, RagConsent.none);

    // The owner's accepted grant does not authorize the other actor.
    await expectLater(
      gateway.query(
        RagRequest(
          question: ragMockAnswerableQuestion,
          scope: const RagScope.account(),
        ),
        context: _context(ragMockOther.userId),
      ),
      _throwsRag(RagFailureCode.consentRequired),
    );

    await gateway.updateConsent(
      RagConsentUpdate(accepted: true, expectedGeneration: 0),
      context: _context(ragMockOther.userId),
    );
    // A note scope must name this actor's own fixture note.
    await expectLater(
      gateway.query(
        RagRequest(
          question: ragMockAnswerableQuestion,
          scope: RagScope.note(ownerFixture.noteId),
        ),
        context: _context(ragMockOther.userId),
      ),
      _throwsRag(RagFailureCode.scopeDenied),
    );

    final RagResult otherAnswer = await gateway.query(
      RagRequest(
        question: ragMockAnswerableQuestion,
        scope: RagScope.note(otherFixture.noteId),
      ),
      context: _context(ragMockOther.userId),
    );
    expect(otherAnswer.isAnswered, isTrue);
    expect(otherAnswer.sources.single.noteId, otherFixture.noteId);
    await gateway.close();
  });

  test(
    'revoke is generation compare-and-set and blocks the next query',
    () async {
      final RagMockClient client = RagMockClient();
      final RagHttpGateway gateway = _gateway(client, () => ragMockOwner);
      await gateway.updateConsent(
        RagConsentUpdate(accepted: true, expectedGeneration: 0),
        context: _context(ragMockOwner.userId),
      );
      final RagConsent revoked = await gateway.updateConsent(
        RagConsentUpdate(accepted: false, expectedGeneration: 1),
        context: _context(ragMockOwner.userId),
      );
      expect(revoked.accepted, isFalse);
      expect(revoked.generation, 2);

      await expectLater(
        gateway.query(
          RagRequest(
            question: ragMockAnswerableQuestion,
            scope: const RagScope.account(),
          ),
          context: _context(ragMockOwner.userId),
        ),
        _throwsRag(RagFailureCode.consentRequired),
      );
      await gateway.close();
    },
  );

  test(
    'the transport refuses foreign hosts, routes, and feature headers',
    () async {
      final RagMockClient client = RagMockClient();
      await expectLater(
        client.get(Uri.parse('https://evil.invalid/ai/rag/consent')),
        throwsA(isA<http.ClientException>()),
      );
      await expectLater(
        client.get(Uri.parse('https://rag-mock.invalid/profile/me')),
        throwsA(isA<http.ClientException>()),
      );
      final http.Request request = http.Request(
        'GET',
        Uri.parse('https://rag-mock.invalid/sync/changes'),
      );
      request.headers['Authorization'] = _bearer(ragMockOwner);
      request.headers['X-Note-Unlock-Grant'] = 'not-a-real-grant';
      await expectLater(
        client.send(request),
        throwsA(isA<http.ClientException>()),
      );
      expect(client.servedRequests, 0);

      // A valid empty changes page is still served, so the refusals above are
      // route-specific and not a blanket failure.
      final http.Response response = await client.get(
        Uri.parse('https://rag-mock.invalid/sync/changes'),
        headers: <String, String>{'Authorization': _bearer(ragMockOwner)},
      );
      expect(response.statusCode, 200);
      expect(client.servedRequests, 1);
      client.close();
    },
  );

  test(
    'the whole real service runs default-off, grant, answer, and source',
    () async {
      final RagMockActor actor = ragMockOwner;
      final RagMockFixture fixture = ragMockFixtureFor(actor);
      final CurrentUserSession session = CurrentUserSession()
        ..setIdentity(
          AuthIdentity(
            userId: actor.userId,
            email: actor.email,
            isEmailVerified: true,
          ),
        );
      final RagMockMemoryStore store = RagMockMemoryStore.forActor(actor);
      final RagMockClient client = RagMockClient();
      final RagHttpGateway gateway = _gateway(client, () => actor);
      final RagAppService service = RagAppService(
        gateway: gateway,
        currentUser: session,
        session: session,
        readLocalState: (String actorId) async {
          final state = await store.read();
          if (state.accountUserId != actorId) {
            throw StateError('the mock store belongs to another actor');
          }
          return state;
        },
      );

      await service.refreshConsent();
      expect(service.state.consent?.accepted, isFalse);

      final RagScope scope = RagScope.note(fixture.noteId);
      await service.ask(question: ragMockAnswerableQuestion, scope: scope);
      expect(service.state.failure?.code, RagFailureCode.consentRequired);
      expect(service.state.result, isNull);

      await service.setConsent(true);
      expect(service.state.consent?.accepted, isTrue);
      expect(service.state.consent?.generation, 1);

      await service.ask(question: ragMockAnswerableQuestion, scope: scope);
      expect(service.state.result?.isAnswered, isTrue);
      final RagSource source = service.state.result!.sources.single;
      expect(source.quote, fixture.quote);
      expect(source.revision, fixture.serverRevision);

      final note = await service.validateSource(source);
      expect(note.id, fixture.noteId);
      expect(
        note.content.substring(source.startOffset, source.endOffset),
        fixture.quote,
      );

      service.dispose();
      await gateway.close();
    },
  );

  test(
    'runtime wires the logical mock endpoint and a seeded fixture store',
    () async {
      final RagMockRuntime runtime = RagMockRuntime.create(ragMockOwner);
      expect(runtime.ragApiBaseUri, ragMockLogicalBase);
      expect(runtime.connection.baseUri, ragMockLogicalBase);

      final String? token = await runtime.connection.tokenProvider(
        forceRefresh: false,
      );
      expect(ragMockJwtSubject(token!), ragMockOwner.userId);

      final RagMockMemoryStore store = runtime.storeFor(
        accountUserId: ragMockOwner.userId,
      ) as RagMockMemoryStore;
      final state = await store.read();
      final RagMockFixture fixture = ragMockFixtureFor(ragMockOwner);
      expect(state.accountUserId, ragMockOwner.userId);
      expect(state.notes.single.id, fixture.noteId);
      expect(state.notes.single.serverRevision, fixture.serverRevision);
      expect(state.notes.single.protection.enabled, isFalse);
      expect(state.notes.single.contentAvailable, isTrue);

      runtime.dispose();
    },
  );

  testWidgets(
    'the mock root injects the typed runtimeUnavailable summary refusal',
    (WidgetTester tester) async {
      // Pump the explicit debug mock root itself (not a reconstructed copy), so
      // the assertion covers the exact composition `main_rag_mock.main` runs.
      rag_mock.main();
      await tester.pumpAndSettle();

      final NoteFlowApp app = tester.widget<NoteFlowApp>(
        find.byType(NoteFlowApp),
      );
      final SummarizeNoteContent? supplied = app.localSummarizer;
      expect(
        supplied,
        isNotNull,
        reason: 'the mock root must wire NoteFlowApp.localSummarizer',
      );

      // The refusal must throw synchronously, before `_summarize` can reach
      // `_ensureService`/`_startService` and therefore the model download path.
      bool threwBeforeAwait = false;
      try {
        supplied!.call('synthetic note body');
      } on SummaryRunFailure catch (failure) {
        threwBeforeAwait = true;
        expect(failure.code, SummaryRunFailureCode.runtimeUnavailable);
      }
      expect(threwBeforeAwait, isTrue);

      // Tear the mock root down so its in-process transport and any startup
      // work are released before the binding checks for pending work.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
