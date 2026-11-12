import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';

import 'rag_widget_harness.dart';

Key _sourceKey(String sourceId) => ValueKey<String>('rag-source-$sourceId');

Future<void> _display(
  WidgetTester tester,
  List<LocalNoteState> notes,
  List<RagSource> sources, {
  void Function(RagSource source)? onOpen,
}) async {
  tester.view
    ..physicalSize = const Size(800, 1600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final RagPresentationHarness harness = RagPresentationHarness(
    local: localState(notes: notes),
  );
  await harness.grant();
  harness.gateway.queryScript.add(answeredResult(sources, answer: 'Answer'));
  await harness.service.ask(
    question: 'Q',
    scope: const RagScope.account(),
  );
  await pumpRagPage(
    tester,
    harness,
    onOpenSource: (RagSource source) async {
      onOpen?.call(source);
      return true;
    },
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a non-contiguous source shows its own id, never the index', (
    WidgetTester tester,
  ) async {
    final LocalNoteState note = ownedNote();
    final RagSource source = sourceFor(note, sourceId: 'S3');
    final List<RagSource> opened = <RagSource>[];
    await _display(tester, <LocalNoteState>[note], <RagSource>[source],
        onOpen: opened.add);

    final Finder button = find.byKey(_sourceKey('S3'));
    expect(button, findsOneWidget);
    expect(
      find.descendant(of: button, matching: find.text('[S3]')),
      findsOneWidget,
    );
    expect(find.text('[S1]'), findsNothing);
    expect(find.text(source.quote), findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(opened, hasLength(1));
    expect(opened.single, source);
  });

  testWidgets('reordered citations keep their exact ids, labels, and callbacks', (
    WidgetTester tester,
  ) async {
    final LocalNoteState first = ownedNote(id: 'note-1', content: 'First body');
    final LocalNoteState second = ownedNote(
      id: 'note-2',
      content: 'Second body',
    );
    final RagSource s1 = sourceFor(first, sourceId: 'S1');
    final RagSource s2 = sourceFor(second, sourceId: 'S2');
    final List<RagSource> opened = <RagSource>[];
    // The array is S2 then S1: index+1 would mislabel both.
    await _display(
      tester,
      <LocalNoteState>[first, second],
      <RagSource>[s2, s1],
      onOpen: opened.add,
    );

    expect(
      find.descendant(
        of: find.byKey(_sourceKey('S2')),
        matching: find.text('[S2]'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(_sourceKey('S1')),
        matching: find.text('[S1]'),
      ),
      findsOneWidget,
    );
    // The exact quotes travel with their own source.
    expect(find.text(s2.quote), findsOneWidget);
    expect(find.text(s1.quote), findsOneWidget);

    await tester.tap(find.byKey(_sourceKey('S2')));
    await tester.pumpAndSettle();
    expect(opened.single, s2);

    await tester.tap(find.byKey(_sourceKey('S1')));
    await tester.pumpAndSettle();
    expect(opened, <RagSource>[s2, s1]);
  });

  testWidgets('the accessible label names the actual source id', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final LocalNoteState note = ownedNote();
    final RagSource source = sourceFor(note, sourceId: 'S3');
    await _display(tester, <LocalNoteState>[note], <RagSource>[source]);

    expect(find.bySemanticsLabel('Open source S3: Title'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Open source S1')), findsNothing);
    handle.dispose();
  });

  testWidgets('a url-shaped title is plain text; the raw source is reported', (
    WidgetTester tester,
  ) async {
    final LocalNoteState note = ownedNote(
      title: 'https://evil.example/steal',
    );
    final RagSource source = sourceFor(note, sourceId: 'S4');
    final List<RagSource> opened = <RagSource>[];
    await _display(tester, <LocalNoteState>[note], <RagSource>[source],
        onOpen: opened.add);

    // The title stays inert text; nothing launches or resolves the URL.
    expect(find.text('https://evil.example/steal'), findsWidgets);
    expect(find.bySemanticsLabel('Open source S4: https://evil.example/steal'),
        findsOneWidget);

    await tester.tap(find.byKey(_sourceKey('S4')));
    await tester.pumpAndSettle();
    expect(opened.single, source);
  });
}
