import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';
import 'package:note_ai_app/presentation/rag/rag_page.dart';

import 'rag_widget_harness.dart';

void main() {
  testWidgets('Ask stays disabled until a canonical grant is known', (
    WidgetTester tester,
  ) async {
    final RagPresentationHarness harness = RagPresentationHarness();
    await pumpRagPage(tester, harness);

    expect(
      tester.widget<FilledButton>(find.byKey(RagPage.askButtonKey)).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(RagPage.cancelButtonKey))
          .onPressed,
      isNull,
    );

    await harness.grant();
    await tester.pumpAndSettle();

    expect(
      tester.widget<FilledButton>(find.byKey(RagPage.askButtonKey)).onPressed,
      isNotNull,
    );
  });

  testWidgets('Ask preserves the exact text and the selected scope', (
    WidgetTester tester,
  ) async {
    final RagPresentationHarness harness = RagPresentationHarness();
    await harness.grant();
    harness.gateway.queryScript.add(notEnoughContextResult());
    await pumpRagPage(tester, harness);

    await tester.enterText(
      find.byKey(RagPage.questionFieldKey),
      '  What did I decide?  ',
    );
    await tester.tap(find.byKey(RagPage.askButtonKey));
    await tester.pumpAndSettle();

    expect(harness.gateway.requests, hasLength(1));
    expect(harness.gateway.requests.single.question, '  What did I decide?  ');
    expect(harness.gateway.requests.single.scope, const RagScope.account());
  });

  testWidgets('Cancel stops the run and a late result cannot apply', (
    WidgetTester tester,
  ) async {
    final RagPresentationHarness harness = RagPresentationHarness();
    await harness.grant();
    final Completer<RagResult> pending = Completer<RagResult>();
    harness.gateway.pendingQuery = pending;
    await pumpRagPage(tester, harness);

    await tester.enterText(find.byKey(RagPage.questionFieldKey), 'Q');
    await tester.tap(find.byKey(RagPage.askButtonKey));
    await tester.pump();

    expect(harness.service.state.queryRunning, isTrue);
    expect(
      tester.widget<FilledButton>(find.byKey(RagPage.askButtonKey)).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(RagPage.cancelButtonKey))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(RagPage.cancelButtonKey));
    await tester.pump();
    expect(harness.service.state.queryRunning, isFalse);
    expect(harness.service.state.result, isNull);

    pending.complete(notEnoughContextResult());
    await tester.pumpAndSettle();
    expect(harness.service.state.result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an old question and answer survive a new failure on the same scope', (
    WidgetTester tester,
  ) async {
    final LocalNoteState note = ownedNote();
    final RagSource source = sourceFor(note);
    final RagPresentationHarness harness = RagPresentationHarness(
      local: localState(notes: <LocalNoteState>[note]),
    );
    await harness.grant();
    harness.gateway.queryScript.add(
      answeredResult(<RagSource>[source], answer: 'Answer one'),
    );
    await pumpRagPage(tester, harness);
    final Finder field = find.byKey(RagPage.questionFieldKey);

    await tester.enterText(field, 'Q1');
    await tester.tap(find.byKey(RagPage.askButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('Answer one'), findsOneWidget);

    harness.gateway.queryScript
      ..clear()
      ..add(
        const RagFailure(RagFailureCode.rateLimited, retryAfterSeconds: 5),
      );
    await tester.enterText(field, 'Q2');
    await tester.tap(find.byKey(RagPage.askButtonKey));
    await tester.pumpAndSettle();

    // The old answer keeps its own question; the new failure never relabels it.
    expect(find.text('Answer one'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(RagPage.answerKey),
        matching: find.text('Q1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(RagPage.answerKey),
        matching: find.text('Q2'),
      ),
      findsNothing,
    );
    expect(find.byKey(RagPage.failureKey), findsOneWidget);
    expect(find.textContaining('Too many requests'), findsOneWidget);
  });

  testWidgets('NOT_ENOUGH_CONTEXT replaces the old answer without a re-ask', (
    WidgetTester tester,
  ) async {
    final LocalNoteState note = ownedNote();
    final RagSource source = sourceFor(note);
    final RagPresentationHarness harness = RagPresentationHarness(
      local: localState(notes: <LocalNoteState>[note]),
    );
    await harness.grant();
    harness.gateway.queryScript.add(
      answeredResult(<RagSource>[source], answer: 'Answer one'),
    );
    await pumpRagPage(tester, harness);
    final Finder field = find.byKey(RagPage.questionFieldKey);

    await tester.enterText(field, 'Q1');
    await tester.tap(find.byKey(RagPage.askButtonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(RagPage.answerKey), findsOneWidget);

    harness.gateway.queryScript
      ..clear()
      ..add(notEnoughContextResult());
    await tester.enterText(field, 'Q2');
    await tester.tap(find.byKey(RagPage.askButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(RagPage.notEnoughContextKey), findsOneWidget);
    expect(find.byKey(RagPage.answerKey), findsNothing);
    expect(find.text('Answer one'), findsNothing);
    // Exactly the two questions the user asked; the refusal never re-asks.
    expect(harness.gateway.requests, hasLength(2));
  });

  testWidgets('a scope change clears the retained pair and cancels its run', (
    WidgetTester tester,
  ) async {
    final LocalNoteState note = ownedNote(id: 'note-1');
    final RagSource source = sourceFor(note);
    final RagPresentationHarness harness = RagPresentationHarness(
      local: localState(notes: <LocalNoteState>[note]),
    );
    await harness.grant();
    harness.gateway.queryScript.add(
      answeredResult(<RagSource>[source], answer: 'Note answer'),
    );
    await pumpRagPage(tester, harness, scope: RagScope.note('note-1'));
    final Finder field = find.byKey(RagPage.questionFieldKey);

    await tester.enterText(field, 'Q1');
    await tester.tap(find.byKey(RagPage.askButtonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(RagPage.answerKey), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('rag-scope-account')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(RagPage.answerKey), findsNothing);
    // The single application owner clears the pair; the view does not just
    // hide what another scope still retains.
    expect(harness.service.state.result, isNull);
    expect(harness.service.state.resultQuestion, isNull);

    final Completer<RagResult> pending = Completer<RagResult>();
    harness.gateway.pendingQuery = pending;
    await tester.tap(
      find.byKey(const ValueKey<String>('rag-scope-note')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(field, 'Q2');
    await tester.tap(find.byKey(RagPage.askButtonKey));
    await tester.pump();
    expect(harness.service.state.queryRunning, isTrue);

    await tester.tap(
      find.byKey(const ValueKey<String>('rag-scope-account')),
    );
    await tester.pump();
    expect(harness.service.state.queryRunning, isFalse);
    pending.complete(notEnoughContextResult());
    await tester.pump();
    expect(harness.service.state.result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an answer never resurrects across note -> account -> note', (
    WidgetTester tester,
  ) async {
    final LocalNoteState note = ownedNote(id: 'note-1');
    final RagSource source = sourceFor(note);
    final RagPresentationHarness harness = RagPresentationHarness(
      local: localState(notes: <LocalNoteState>[note]),
    );
    await harness.grant();
    harness.gateway.queryScript.add(
      answeredResult(<RagSource>[source], answer: 'Note answer'),
    );
    await pumpRagPage(tester, harness, scope: RagScope.note('note-1'));
    final Finder field = find.byKey(RagPage.questionFieldKey);

    await tester.enterText(field, 'Q1');
    await tester.tap(find.byKey(RagPage.askButtonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(RagPage.answerKey), findsOneWidget);

    final int queries = harness.gateway.requests.length;
    final int writes = harness.gateway.updates.length;

    await tester.tap(
      find.byKey(const ValueKey<String>('rag-scope-account')),
    );
    await tester.pumpAndSettle();
    expect(harness.service.state.result, isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('rag-scope-note')),
    );
    await tester.pumpAndSettle();

    // Returning to the original scope must not revive the cleared answer, and
    // selecting a scope performs no query or grant write.
    expect(find.byKey(RagPage.answerKey), findsNothing);
    expect(harness.service.state.result, isNull);
    expect(harness.service.state.resultQuestion, isNull);
    expect(harness.gateway.requests, hasLength(queries));
    expect(harness.gateway.updates, hasLength(writes));
  });

  testWidgets('mounting a different initial scope clears a retained pair', (
    WidgetTester tester,
  ) async {
    final LocalNoteState note = ownedNote(id: 'note-1');
    final RagSource source = sourceFor(note);
    final RagPresentationHarness harness = RagPresentationHarness(
      local: localState(notes: <LocalNoteState>[note]),
    );
    await harness.grant();
    harness.gateway.queryScript.add(
      answeredResult(<RagSource>[source], answer: 'Account answer'),
    );
    // The service already holds an account-scope pair from a previous route.
    await harness.service.ask(question: 'Q1', scope: const RagScope.account());
    expect(harness.service.state.result, isNotNull);

    // A new route mounts on a note scope; the foreign pair is cleared through
    // the single owner instead of being hidden until that scope is revisited.
    await pumpRagPage(tester, harness, scope: RagScope.note('note-1'));
    await tester.pumpAndSettle();
    expect(harness.service.state.scope, RagScope.note('note-1'));
    expect(harness.service.state.result, isNull);
    expect(harness.service.state.resultQuestion, isNull);
    expect(find.byKey(RagPage.answerKey), findsNothing);
  });

  testWidgets('typed quota, index, and auth failures are localized', (
    WidgetTester tester,
  ) async {
    final RagPresentationHarness harness = RagPresentationHarness();
    await harness.grant();
    await pumpRagPage(tester, harness);
    final Finder field = find.byKey(RagPage.questionFieldKey);
    final List<(RagFailureCode, String)> cases = <(RagFailureCode, String)>[
      (RagFailureCode.rateLimited, 'Too many requests'),
      (RagFailureCode.indexNotReady, 'not ready yet'),
      (RagFailureCode.unauthorized, 'Sign in again'),
      (RagFailureCode.providerUnavailable, 'temporarily unavailable'),
      (RagFailureCode.livePolicyNotConfigured, 'not enabled for this account'),
    ];

    for (final (RagFailureCode code, String substring) in cases) {
      harness.gateway.queryScript
        ..clear()
        ..add(RagFailure(code));
      await tester.enterText(field, 'Q-${code.name}');
      await tester.tap(find.byKey(RagPage.askButtonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(RagPage.failureKey), findsOneWidget);
      expect(find.textContaining(substring), findsOneWidget);
      expect(find.textContaining('RagFailureCode'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
    }
  });
}
