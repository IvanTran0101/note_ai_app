import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';
import 'package:note_ai_app/presentation/rag/rag_page.dart';

import 'rag_widget_harness.dart';

void main() {
  testWidgets('narrow width and large text scale stay overflow-free', (
    WidgetTester tester,
  ) async {
    tester.view
      ..physicalSize = const Size(320, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final LocalNoteState note = ownedNote(content: 'A longer synthetic body');
    final RagSource source = sourceFor(note, sourceId: 'S1');
    final RagPresentationHarness harness = RagPresentationHarness(
      local: localState(notes: <LocalNoteState>[note]),
    );
    await harness.grant();
    harness.gateway.queryScript.add(
      answeredResult(<RagSource>[source], answer: 'A wrapped synthetic answer'),
    );
    await harness.service.ask(
      question: 'A question that should wrap on a narrow screen',
      scope: const RagScope.account(),
    );

    await pumpRagPage(
      tester,
      harness,
      textScaler: const TextScaler.linear(2),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(RagPage.askButtonKey), findsOneWidget);
    expect(
      find.byKey(ValueKey<String>('rag-source-${source.sourceId}')),
      findsOneWidget,
    );
  });

  testWidgets('Ctrl+Enter asks while plain Enter stays multiline', (
    WidgetTester tester,
  ) async {
    final RagPresentationHarness harness = RagPresentationHarness();
    await harness.grant();
    harness.gateway.queryScript.add(notEnoughContextResult());
    await pumpRagPage(tester, harness);
    final Finder field = find.byKey(RagPage.questionFieldKey);

    await tester.enterText(field, 'keyboard question');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(harness.gateway.requests, isEmpty);

    await tester.enterText(field, 'keyboard question');
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(harness.gateway.requests, hasLength(1));
    expect(harness.gateway.requests.single.question, 'keyboard question');
  });

  testWidgets('the source button is reachable with button semantics', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final LocalNoteState note = ownedNote();
    final RagSource source = sourceFor(note, sourceId: 'S1');
    final RagPresentationHarness harness = RagPresentationHarness(
      local: localState(notes: <LocalNoteState>[note]),
    );
    await harness.grant();
    harness.gateway.queryScript.add(
      answeredResult(<RagSource>[source], answer: 'Answer'),
    );
    await harness.service.ask(
      question: 'Q',
      scope: const RagScope.account(),
    );
    await pumpRagPage(tester, harness);
    await tester.pumpAndSettle();

    final Finder sourceFinder = find.byKey(
      ValueKey<String>('rag-source-${source.sourceId}'),
    );
    expect(
      find.bySemanticsLabel(RegExp('Open source S1')),
      findsWidgets,
    );
    final SemanticsNode node = tester.getSemantics(sourceFinder);
    expect(node.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets('disposing the page cancels its run and keeps the service usable', (
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

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    expect(harness.service.state.queryRunning, isFalse);

    pending.complete(notEnoughContextResult());
    await tester.pump();

    harness.gateway
      ..pendingQuery = null
      ..queryScript.clear()
      ..queryScript.add(notEnoughContextResult());
    await harness.service.ask(
      question: 'again',
      scope: const RagScope.account(),
    );
    expect(harness.service.state.result, isNotNull);
    expect(harness.gateway.closes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing an idle page never cancels a question it did not '
      'start', (WidgetTester tester) async {
    final RagPresentationHarness harness = RagPresentationHarness();
    await harness.grant();
    final Completer<RagResult> pending = Completer<RagResult>();
    harness.gateway.pendingQuery = pending;
    await pumpRagPage(tester, harness);
    await tester.pump();

    // Another owner starts a question on the shared service while the page is
    // idle and has submitted nothing.
    final Future<void> run = harness.service.ask(
      question: 'external',
      scope: const RagScope.account(),
    );
    await tester.pump();
    expect(harness.service.state.queryRunning, isTrue);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    expect(harness.service.state.queryRunning, isTrue);

    pending.complete(notEnoughContextResult());
    await run;
    expect(harness.service.state.result, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
