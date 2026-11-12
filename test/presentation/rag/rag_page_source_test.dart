import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';

import 'rag_widget_harness.dart';

Key _sourceKey(RagSource source) =>
    ValueKey<String>('rag-source-${source.sourceId}');

Future<RagPresentationHarness> _displaySources(
  WidgetTester tester,
  List<LocalNoteState> notes,
  List<RagSource> sources, {
  Future<bool> Function(RagSource source)? onOpenSource,
}) async {
  tester.view
    ..physicalSize = const Size(800, 1600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final RagPresentationHarness harness = RagPresentationHarness(
    local: localState(notes: notes),
  );
  await harness.grant();
  harness.gateway.queryScript.add(
    answeredResult(sources, answer: 'Answer'),
  );
  await harness.service.ask(
    question: 'Q',
    scope: const RagScope.account(),
  );
  await pumpRagPage(tester, harness, onOpenSource: onOpenSource);
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  testWidgets('reports the exact source and clears busy on success', (
    WidgetTester tester,
  ) async {
    final LocalNoteState note = ownedNote();
    final RagSource source = sourceFor(note, sourceId: 'S1');
    final List<RagSource> opened = <RagSource>[];
    await _displaySources(
      tester,
      <LocalNoteState>[note],
      <RagSource>[source],
      onOpenSource: (RagSource candidate) async {
        opened.add(candidate);
        return true;
      },
    );

    expect(find.byKey(_sourceKey(source)), findsOneWidget);
    expect(find.text('[S1]'), findsOneWidget);
    expect(find.text(note.title), findsWidgets);
    expect(find.text(source.quote), findsOneWidget);

    await tester.tap(find.byKey(_sourceKey(source)));
    await tester.pumpAndSettle();

    expect(opened, hasLength(1));
    expect(opened.single, source);
    expect(find.byKey(const ValueKey<String>('rag-source-error')), findsNothing);
  });

  testWidgets('a false callback is refused safely', (
    WidgetTester tester,
  ) async {
    final LocalNoteState note = ownedNote();
    final RagSource source = sourceFor(note);
    await _displaySources(
      tester,
      <LocalNoteState>[note],
      <RagSource>[source],
      onOpenSource: (RagSource _) async => false,
    );

    await tester.tap(find.byKey(_sourceKey(source)));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('rag-source-error')),
      findsOneWidget,
    );
    expect(find.textContaining('could not be opened'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a typed callback failure is mapped without leaking details', (
    WidgetTester tester,
  ) async {
    final LocalNoteState note = ownedNote();
    final RagSource source = sourceFor(note);
    await _displaySources(
      tester,
      <LocalNoteState>[note],
      <RagSource>[source],
      onOpenSource: (RagSource _) async =>
          throw const RagFailure(RagFailureCode.sourceChanged),
    );

    await tester.tap(find.byKey(_sourceKey(source)));
    await tester.pumpAndSettle();

    expect(find.textContaining('The source changed'), findsOneWidget);
    expect(find.textContaining('RagFailureCode'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('busy state disables the other citation until the callback ends', (
    WidgetTester tester,
  ) async {
    final LocalNoteState first = ownedNote(id: 'note-1');
    final LocalNoteState second = ownedNote(
      id: 'note-2',
      content: 'Second body',
    );
    final RagSource sourceOne = sourceFor(first, sourceId: 'source-1');
    final RagSource sourceTwo = sourceFor(second, sourceId: 'source-2');
    final Completer<bool> gate = Completer<bool>();
    await _displaySources(
      tester,
      <LocalNoteState>[first, second],
      <RagSource>[sourceOne, sourceTwo],
      onOpenSource: (RagSource _) => gate.future,
    );

    await tester.tap(find.byKey(_sourceKey(sourceOne)));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(_sourceKey(sourceOne)),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<OutlinedButton>(find.byKey(_sourceKey(sourceTwo))).onPressed,
      isNull,
    );

    gate.complete(true);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester.widget<OutlinedButton>(find.byKey(_sourceKey(sourceTwo))).onPressed,
      isNotNull,
    );
  });

  testWidgets('a callback that resolves after dispose is guarded', (
    WidgetTester tester,
  ) async {
    final LocalNoteState note = ownedNote();
    final RagSource source = sourceFor(note);
    final Completer<bool> gate = Completer<bool>();
    await _displaySources(
      tester,
      <LocalNoteState>[note],
      <RagSource>[source],
      onOpenSource: (RagSource _) => gate.future,
    );

    await tester.tap(find.byKey(_sourceKey(source)));
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    gate.complete(true);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
