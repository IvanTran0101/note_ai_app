import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:note_ai_app/application/auth/auth_models.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/revision_source.dart';
import 'package:note_ai_app/dev/m06_local_connection.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/note_intelligence/i_rag_gateway.dart';
import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';
import 'package:note_ai_app/infrastructure/configuration/note_connection.dart';
import 'package:note_ai_app/main.dart';
import 'package:note_ai_app/presentation/auth/controllers/auth_controller.dart';
import 'package:note_ai_app/presentation/notes/note_detail_page.dart';
import 'package:note_ai_app/presentation/rag/rag_page.dart';
import 'package:note_ai_app/presentation/workspace/workspace_shell.dart';

import '../application/note_intelligence/rag_test_support.dart';
import '../infrastructure/notes/note_repository_test_support.dart';

final class _SilentSource implements IRevisionSource {
  @override
  Stream<RevisionNotice> get notices => const Stream.empty();
  @override
  void start() {}
  @override
  void reconnect() {}
  @override
  Future<void> dispose() async {}
}

/// Delegates to the shared [FakeRagGateway] while recording call order, so a
/// test can prove the fresh sync happened before the single canonical GET.
final class _RecordingGateway implements IRagGateway {
  _RecordingGateway(this.inner, this.events);

  final FakeRagGateway inner;
  final List<String> events;

  @override
  Future<RagConsent> readConsent({required RagCallContext context}) {
    events.add('rag:readConsent');
    return inner.readConsent(context: context);
  }

  @override
  Future<RagConsent> updateConsent(
    RagConsentUpdate update, {
    required RagCallContext context,
  }) {
    events.add('rag:updateConsent');
    return inner.updateConsent(update, context: context);
  }

  @override
  Future<RagResult> query(
    RagRequest request, {
    required RagCallContext context,
  }) {
    events.add('rag:query');
    return inner.query(request, context: context);
  }

  @override
  Future<void> close() {
    events.add('rag:close');
    return inner.close();
  }
}

void main() {
  const String actor = 'm06-dev-owner';
  const String content = 'Body 😀 with tiếng Việt words';
  const String quote = '😀 with tiếng';

  _RagAppHarness buildHarness({bool withRag = true}) {
    final Map<String, FakeLocalSyncStore> stores =
        <String, FakeLocalSyncStore>{};
    FakeLocalSyncStore createStore(String accountUserId) => FakeLocalSyncStore(
      accountUserId: accountUserId,
      initial: localState(
        actorId: accountUserId,
        notes: <LocalNoteState>[
          ownedNote(
            id: 'note-1',
            ownerId: accountUserId,
            title: 'Title',
            content: content,
            serverRevision: 3,
          ),
          // A second, unrelated note so a draft can be made elsewhere without
          // invalidating an answer that cites note-1.
          ownedNote(
            id: 'note-2',
            ownerId: accountUserId,
            title: 'Second',
            content: 'Second note body',
            serverRevision: 3,
          ),
        ],
      ),
    );
    stores[actor] = createStore(actor);
    final FakeRagGateway fake = FakeRagGateway(
      consentScript: <Object>[RagConsent(accepted: true, generation: 1)],
    );
    final List<String> events = <String>[];
    final _RecordingGateway? gateway = withRag
        ? _RecordingGateway(fake, events)
        : null;
    // The negative fixture must keep ask-notes hidden even though the generated
    // public config now legitimately carries a live RAG endpoint. An explicit
    // non-HTTPS URI is the existing composition seam: the root validates the
    // explicit value, rejects it, and never falls back to generated config.
    final Uri? ragApiBaseUri = withRag
        ? null
        : Uri.parse('http://disabled.invalid');
    var failSync = false;
    Completer<void>? syncGate;
    final MockClient syncClient = MockClient((http.Request request) async {
      events.add('sync');
      final Completer<void>? gate = syncGate;
      if (gate != null) await gate.future;
      if (failSync) {
        throw http.ClientException('offline');
      }
      // This fixture intentionally models the older plain API. The new root
      // probes V3 first and must fall back without treating it as deployed.
      if (request.url.path == '/sync/v3/changes') {
        return http.Response('{"code":"NOT_FOUND"}', 404);
      }
      return http.Response(
        '{"items":[],"nextCursor":null,"hasMore":false}',
        200,
      );
    });
    final CurrentUserSession session = CurrentUserSession()
      ..setIdentity(
        AuthIdentity(
          userId: actor,
          email: 'owner@example.invalid',
          isEmailVerified: true,
        ),
      );
    final AuthController auth = AuthController(
      authenticationAppService: null,
      initialUser: AuthUserDto.fromIdentity(session.identity!),
    );
    return _RagAppHarness(
      session: session,
      auth: auth,
      stores: stores,
      createStore: createStore,
      primaryActor: actor,
      fake: fake,
      gateway: gateway,
      ragApiBaseUri: ragApiBaseUri,
      events: events,
      syncClient: syncClient,
      setFailSync: (bool value) => failSync = value,
      setSyncGate: (Completer<void>? gate) => syncGate = gate,
      connection: NoteConnection(
        baseUri: Uri.parse('https://sync.test'),
        tokenProvider: ({required bool forceRefresh}) async =>
            devToken(actor, 'access'),
        client: syncClient,
        revisionSourceFor: (_) => _SilentSource(),
      ),
    );
  }

  Future<void> pumpApp(WidgetTester tester, _RagAppHarness harness) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      NoteFlowApp(
        authController: harness.auth,
        currentUserSession: harness.session,
        localSyncStoreFactory: ({required String accountUserId}) =>
            harness.storeFor(accountUserId),
        connection: harness.connection,
        ragGateway: harness.gateway,
        ragApiBaseUri: harness.ragApiBaseUri,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openAccountRag(WidgetTester tester) async {
    await tester.tap(find.byKey(WorkspaceShell.askNotesKey));
    await tester.pumpAndSettle();
    expect(find.byKey(RagPage.questionFieldKey), findsOneWidget);
  }

  Future<void> askAndDisplaySource(
    WidgetTester tester,
    _RagAppHarness harness,
  ) async {
    final LocalNoteState note = harness.store.state.notes.firstWhere(
      (LocalNoteState candidate) => candidate.id == 'note-1',
    );
    final RagSource source = sourceFor(
      note,
      sourceId: 'source-1',
      quote: quote,
    );
    harness.fake.queryScript
      ..clear()
      ..add(answeredResult(<RagSource>[source]));
    await tester.enterText(
      find.byKey(RagPage.questionFieldKey),
      'What did I write?',
    );
    await tester.pump();
    await tester.tap(find.byKey(RagPage.askButtonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(RagPage.answerKey), findsOneWidget);
  }

  testWidgets('account action opens the shared ask-notes screen', (
    tester,
  ) async {
    final _RagAppHarness harness = buildHarness();
    await pumpApp(tester, harness);
    expect(find.byKey(WorkspaceShell.askNotesKey), findsOneWidget);
    await openAccountRag(tester);
    expect(harness.fake.calls, contains('readConsent'));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    harness.syncClient.close();
  });

  testWidgets(
    'citation open syncs first, reads consent once, and reveals the exact span',
    (tester) async {
      final _RagAppHarness harness = buildHarness();
      await pumpApp(tester, harness);
      await openAccountRag(tester);
      await askAndDisplaySource(tester, harness);

      harness.events.clear();
      await tester.tap(
        find.byKey(const ValueKey<String>('rag-source-source-1')),
      );
      await tester.pumpAndSettle();

      final List<String> events = harness.events;
      expect(
        events.where((String e) => e == 'rag:readConsent').length,
        1,
        reason: 'exactly one canonical consent read for one source open',
      );
      expect(events, contains('sync'));
      expect(
        events.indexOf('rag:readConsent'),
        greaterThan(events.lastIndexOf('sync')),
        reason: 'fresh sync must complete before the canonical GET',
      );
      expect(events.where((String e) => e == 'rag:query'), isEmpty);

      // The RAG route is gone and the cited note is open with the exact span.
      expect(find.byKey(RagPage.questionFieldKey), findsNothing);
      final TextEditingController controller = tester
          .widget<TextField>(find.byKey(NoteDetailPage.contentFieldKey))
          .controller!;
      final TextSelection selection = controller.selection;
      expect(controller.text.substring(selection.start, selection.end), quote);
      expect(selection.start, content.indexOf(quote));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      harness.syncClient.close();
    },
  );

  testWidgets('sync failure refuses without a canonical GET or navigation', (
    tester,
  ) async {
    final _RagAppHarness harness = buildHarness();
    await pumpApp(tester, harness);
    await openAccountRag(tester);
    await askAndDisplaySource(tester, harness);

    harness.setFailSync(true);
    harness.events.clear();
    await tester.tap(find.byKey(const ValueKey<String>('rag-source-source-1')));
    await tester.pumpAndSettle();

    expect(harness.events.where((String e) => e == 'rag:readConsent'), isEmpty);
    expect(find.byKey(RagPage.questionFieldKey), findsOneWidget);
    expect(find.byKey(NoteDetailPage.contentFieldKey), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    harness.syncClient.close();
  });

  testWidgets('a dirty editor refuses a citation open', (tester) async {
    final _RagAppHarness harness = buildHarness();
    await pumpApp(tester, harness);

    // Open the cited note in the workspace and make it dirty first.
    await tester.tap(find.byKey(WorkspaceShell.notesDestinationKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title').first);
    await tester.pumpAndSettle();
    expect(find.byKey(NoteDetailPage.contentFieldKey), findsOneWidget);
    await tester.enterText(
      find.byKey(NoteDetailPage.contentFieldKey),
      'draft in progress',
    );
    await tester.pump();
    // Force the autosave that a focus loss triggers to fail, so the draft stays
    // dirty (and the stored note keeps its original text/revision).
    harness.store.failure = StateError('offline');

    await openAccountRag(tester);
    await askAndDisplaySource(tester, harness);

    harness.events.clear();
    await tester.tap(find.byKey(const ValueKey<String>('rag-source-source-1')));
    await tester.pumpAndSettle();
    expect(harness.events.where((String e) => e == 'rag:readConsent'), isEmpty);
    expect(find.byKey(RagPage.questionFieldKey), findsOneWidget);

    // Disposing the editor cancels its pending autosave timer.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    harness.syncClient.close();
  });

  testWidgets('root dispose closes the injected gateway exactly once', (
    tester,
  ) async {
    final _RagAppHarness harness = buildHarness();
    await pumpApp(tester, harness);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(harness.fake.closes, 1);
    harness.syncClient.close();
  });

  testWidgets('settings shows the ask-notes consent tile separately', (
    tester,
  ) async {
    final _RagAppHarness harness = buildHarness();
    await pumpApp(tester, harness);
    await tester.tap(find.byKey(WorkspaceShell.settingsKey));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('settings-rag-consent')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    harness.syncClient.close();
  });

  testWidgets('a citation whose local revision moved is refused', (
    tester,
  ) async {
    final _RagAppHarness harness = buildHarness();
    await pumpApp(tester, harness);
    await openAccountRag(tester);
    await askAndDisplaySource(tester, harness);

    // Move the stored note revision without notifying the displayed answer.
    await harness.store.replace(
      localState(
        actorId: actor,
        notes: <LocalNoteState>[
          ownedNote(
            id: 'note-1',
            ownerId: actor,
            title: 'Title',
            content: content,
            serverRevision: 4,
          ),
        ],
      ),
    );

    harness.events.clear();
    await tester.tap(find.byKey(const ValueKey<String>('rag-source-source-1')));
    await tester.pumpAndSettle();
    // The local revalidation seen through the sync notification clears the
    // answer whose citation no longer matches; no canonical GET is needed.
    expect(harness.events.where((String e) => e == 'rag:readConsent'), isEmpty);
    expect(harness.events.where((String e) => e == 'rag:query'), isEmpty);
    expect(find.byKey(RagPage.questionFieldKey), findsOneWidget);
    expect(find.byKey(RagPage.answerKey), findsNothing);
    expect(find.byKey(NoteDetailPage.contentFieldKey), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    harness.syncClient.close();
  });

  testWidgets('inactivity clears the answer and resume re-reads the grant', (
    tester,
  ) async {
    final _RagAppHarness harness = buildHarness();
    await pumpApp(tester, harness);
    await openAccountRag(tester);
    await askAndDisplaySource(tester, harness);
    expect(find.byKey(RagPage.answerKey), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.byKey(RagPage.answerKey), findsNothing);

    final int readsBefore = harness.events
        .where((String e) => e == 'rag:readConsent')
        .length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      harness.events.where((String e) => e == 'rag:readConsent').length,
      greaterThan(readsBefore),
      reason: 'resume re-reads the canonical grant',
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    harness.syncClient.close();
  });

  testWidgets('full-app logout closes the RAG route without late errors', (
    tester,
  ) async {
    final _RagAppHarness harness = buildHarness();
    await pumpApp(tester, harness);
    await openAccountRag(tester);
    await askAndDisplaySource(tester, harness);
    expect(find.byKey(RagPage.answerKey), findsOneWidget);

    // A real AuthController sign-out notification: the bound session clears
    // first (as AuthenticationAppService does), then the controller notifies
    // its listeners. The workspace rebuilds for the public route while the
    // account-scoped sync presentation controller is being torn down.
    harness.session.clear();
    await harness.auth.logout();
    await tester.pumpAndSettle();

    expect(find.byKey(RagPage.questionFieldKey), findsNothing);
    expect(find.byKey(RagPage.answerKey), findsNothing);
    expect(find.byKey(NoteDetailPage.contentFieldKey), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    harness.syncClient.close();
  });

  testWidgets('auth account switch closes the RAG route and clears old state', (
    tester,
  ) async {
    final _RagAppHarness harness = buildHarness();
    await pumpApp(tester, harness);
    await openAccountRag(tester);
    await askAndDisplaySource(tester, harness);
    expect(find.byKey(RagPage.answerKey), findsOneWidget);

    // The bound session moves to a different account, then the real auth
    // controller notifies. The old question/answer must be gone and the next
    // account must use its own account-bound store.
    harness.session.setIdentity(
      AuthIdentity(
        userId: 'm06-dev-other',
        email: 'other@example.invalid',
        isEmailVerified: true,
      ),
    );
    harness.auth.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.byKey(RagPage.questionFieldKey), findsNothing);
    expect(find.byKey(RagPage.answerKey), findsNothing);
    expect(harness.stores.containsKey('m06-dev-other'), isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    harness.syncClient.close();
  });

  testWidgets(
    'an unsupported explicit RAG endpoint is hidden even with Sync configured',
    (tester) async {
      final _RagAppHarness harness = buildHarness(withRag: false);
      await pumpApp(tester, harness);

      // The legacy Sync connection is present and the generated public config
      // now carries a RAG endpoint, but the explicit endpoint injected here is
      // unsupported (non-HTTPS), so the feature stays honestly hidden.
      expect(find.byKey(WorkspaceShell.askNotesKey), findsNothing);

      await tester.tap(find.byKey(WorkspaceShell.notesDestinationKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Title').first);
      await tester.pumpAndSettle();
      expect(find.byKey(NoteDetailPage.contentFieldKey), findsOneWidget);
      expect(find.byKey(NoteDetailPage.askNotesKey), findsNothing);

      await tester.tap(find.byKey(WorkspaceShell.settingsKey));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('settings-rag-consent')),
        findsNothing,
        reason: 'an unsupported endpoint means no consent surface is offered',
      );
      expect(
        harness.events.where((String e) => e.startsWith('rag:')),
        isEmpty,
        reason: 'no RAG action or consent read without a valid RAG endpoint',
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      harness.syncClient.close();
    },
  );

  testWidgets('account change during the citation sync refuses late apply', (
    tester,
  ) async {
    final _RagAppHarness harness = buildHarness();
    await pumpApp(tester, harness);
    await openAccountRag(tester);
    await askAndDisplaySource(tester, harness);

    final Completer<void> gate = Completer<void>();
    harness.setSyncGate(gate);
    harness.events.clear();
    await tester.tap(find.byKey(const ValueKey<String>('rag-source-source-1')));
    await tester.pump();

    // A real identity transition while the fresh sync is still in flight.
    harness.session.clear();
    harness.session.setIdentity(
      AuthIdentity(
        userId: 'm06-dev-other',
        email: 'other@example.invalid',
        isEmailVerified: true,
      ),
    );
    gate.complete();
    await tester.pumpAndSettle();

    expect(
      harness.events.where((String e) => e == 'rag:readConsent'),
      isEmpty,
      reason: 'no canonical GET after the cited session changed',
    );
    expect(find.byKey(NoteDetailPage.contentFieldKey), findsNothing);
    expect(find.byKey(RagPage.questionFieldKey), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    harness.syncClient.close();
  });

  testWidgets('a draft made during the citation sync refuses late apply', (
    tester,
  ) async {
    final _RagAppHarness harness = buildHarness();
    await pumpApp(tester, harness);

    // Open the unrelated note-2 and keep its live editor before the RAG route
    // is pushed on top of it. Its draft leaves the displayed note-1 answer
    // untouched, so only the workspace's unsaved-changes guard can refuse.
    await tester.tap(find.byKey(WorkspaceShell.notesDestinationKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second').first);
    await tester.pumpAndSettle();
    final TextEditingController content = tester
        .widget<TextField>(find.byKey(NoteDetailPage.contentFieldKey))
        .controller!;

    await openAccountRag(tester);
    await askAndDisplaySource(tester, harness);

    final Completer<void> gate = Completer<void>();
    harness.setSyncGate(gate);
    harness.events.clear();
    await tester.tap(find.byKey(const ValueKey<String>('rag-source-source-1')));
    await tester.pump();

    // The editor is behind the RAG route but still live. A real draft made
    // while the fresh sync is in flight marks the workspace dirty, so the late
    // completion must not reach the canonical GET.
    harness.store.failure = StateError('offline');
    content.text = 'draft during sync';
    await tester.pump();
    expect(
      find.byKey(RagPage.answerKey),
      findsOneWidget,
      reason: 'the unrelated draft must not clear the displayed note-1 answer',
    );
    final int readsBeforeGate = harness.events
        .where((String e) => e == 'rag:readConsent')
        .length;
    gate.complete();
    await tester.pumpAndSettle();

    expect(
      harness.events.where((String e) => e == 'rag:readConsent').length,
      readsBeforeGate,
      reason: 'no canonical GET once the workspace had unsaved changes',
    );
    expect(find.byKey(NoteDetailPage.contentFieldKey), findsNothing);
    expect(find.byKey(RagPage.questionFieldKey), findsOneWidget);

    // Disposing the editor cancels its pending autosave timer.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    harness.syncClient.close();
  });

  testWidgets(
    'a replaced displayed result during the citation sync refuses late apply',
    (tester) async {
      final _RagAppHarness harness = buildHarness();
      await pumpApp(tester, harness);
      await openAccountRag(tester);
      await askAndDisplaySource(tester, harness);

      final LocalNoteState note = harness.store.state.notes.firstWhere(
        (LocalNoteState candidate) => candidate.id == 'note-1',
      );
      // A distinct answer object that still cites the same note and span, so
      // the source-open membership check alone would not refuse it.
      final RagSource sameSource = sourceFor(
        note,
        sourceId: 'source-1',
        quote: quote,
      );

      final Completer<void> gate = Completer<void>();
      harness.setSyncGate(gate);
      harness.events.clear();
      await tester.tap(
        find.byKey(const ValueKey<String>('rag-source-source-1')),
      );
      await tester.pump();

      // A second question replaces the displayed result while the fresh sync is
      // still in flight. The new answer cites the same source, so only the
      // captured pre-frame result identity can refuse the late open.
      harness.fake.queryScript.add(
        answeredResult(
          <RagSource>[sameSource],
          answer: 'Replaced answer [S1]',
          requestId: 'req-2',
        ),
      );
      await tester.tap(find.byKey(RagPage.askButtonKey));
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Replaced answer [S1]'),
        findsOneWidget,
        reason: 'the replacement answer must be displayed before the sync ends',
      );
      final int readsAfterReplacement = harness.events
          .where((String e) => e == 'rag:readConsent')
          .length;

      gate.complete();
      await tester.pumpAndSettle();

      expect(
        harness.events.where((String e) => e == 'rag:readConsent').length,
        readsAfterReplacement,
        reason:
            'no canonical GET after the captured displayed result was replaced',
      );
      expect(find.byKey(NoteDetailPage.contentFieldKey), findsNothing);
      expect(find.byKey(RagPage.questionFieldKey), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      harness.syncClient.close();
    },
  );

  testWidgets('full-app logout during the citation sync refuses late apply', (
    tester,
  ) async {
    final _RagAppHarness harness = buildHarness();
    await pumpApp(tester, harness);
    await openAccountRag(tester);
    await askAndDisplaySource(tester, harness);

    final Completer<void> gate = Completer<void>();
    harness.setSyncGate(gate);
    harness.events.clear();
    await tester.tap(find.byKey(const ValueKey<String>('rag-source-source-1')));
    await tester.pump();

    // The real auth notification: clear the bound session, then notify.
    harness.session.clear();
    await harness.auth.logout();
    gate.complete();
    await tester.pumpAndSettle();

    expect(harness.events.where((String e) => e == 'rag:readConsent'), isEmpty);
    expect(find.byKey(RagPage.questionFieldKey), findsNothing);
    expect(find.byKey(RagPage.answerKey), findsNothing);
    expect(find.byKey(NoteDetailPage.contentFieldKey), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    harness.syncClient.close();
  });

  testWidgets('inactivity during the citation sync refuses late apply', (
    tester,
  ) async {
    final _RagAppHarness harness = buildHarness();
    await pumpApp(tester, harness);
    await openAccountRag(tester);
    await askAndDisplaySource(tester, harness);

    final Completer<void> gate = Completer<void>();
    harness.setSyncGate(gate);
    harness.events.clear();
    await tester.tap(find.byKey(const ValueKey<String>('rag-source-source-1')));
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    gate.complete();
    await tester.pumpAndSettle();

    expect(harness.events.where((String e) => e == 'rag:readConsent'), isEmpty);
    expect(find.byKey(NoteDetailPage.contentFieldKey), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    harness.syncClient.close();
  });

  testWidgets(
    'a closed RAG route during the citation sync refuses late apply',
    (tester) async {
      final _RagAppHarness harness = buildHarness();
      await pumpApp(tester, harness);
      await openAccountRag(tester);
      await askAndDisplaySource(tester, harness);

      final Completer<void> gate = Completer<void>();
      harness.setSyncGate(gate);
      harness.events.clear();
      await tester.tap(
        find.byKey(const ValueKey<String>('rag-source-source-1')),
      );
      await tester.pump();

      await tester.pageBack();
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();

      expect(
        harness.events.where((String e) => e == 'rag:readConsent'),
        isEmpty,
      );
      expect(find.byKey(RagPage.questionFieldKey), findsNothing);
      expect(find.byKey(NoteDetailPage.contentFieldKey), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      harness.syncClient.close();
    },
  );

  testWidgets('a citation sync that exceeds its budget never applies', (
    tester,
  ) async {
    final _RagAppHarness harness = buildHarness();
    await pumpApp(tester, harness);
    await openAccountRag(tester);
    await askAndDisplaySource(tester, harness);

    final Completer<void> gate = Completer<void>();
    harness.setSyncGate(gate);
    harness.events.clear();
    await tester.tap(find.byKey(const ValueKey<String>('rag-source-source-1')));
    await tester.pump();

    // The single 26-second navigation deadline fires while the sync hangs.
    await tester.pump(const Duration(seconds: 27));
    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(NoteDetailPage.contentFieldKey), findsNothing);
    expect(find.byKey(RagPage.questionFieldKey), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    harness.syncClient.close();
  });
}

final class _RagAppHarness {
  _RagAppHarness({
    required this.session,
    required this.auth,
    required this.stores,
    required this.createStore,
    required this.primaryActor,
    required this.fake,
    required this.gateway,
    required this.ragApiBaseUri,
    required this.events,
    required this.syncClient,
    required this.setFailSync,
    required this.setSyncGate,
    required this.connection,
  });

  final CurrentUserSession session;
  final AuthController auth;

  /// One account-bound store per actor, exactly like the production factory;
  /// never a single fake reused across accounts.
  final Map<String, FakeLocalSyncStore> stores;
  final FakeLocalSyncStore Function(String accountUserId) createStore;
  final String primaryActor;
  final FakeRagGateway fake;
  final _RecordingGateway? gateway;
  final Uri? ragApiBaseUri;
  final List<String> events;
  final MockClient syncClient;
  final void Function(bool value) setFailSync;
  final void Function(Completer<void>? gate) setSyncGate;
  final NoteConnection connection;

  FakeLocalSyncStore storeFor(String accountUserId) =>
      stores.putIfAbsent(accountUserId, () => createStore(accountUserId));

  FakeLocalSyncStore get store => storeFor(primaryActor);
}
