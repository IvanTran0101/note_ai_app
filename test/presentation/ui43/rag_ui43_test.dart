import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';
import 'package:note_ai_app/presentation/rag/rag_page.dart';

import '../rag/rag_widget_harness.dart';

void main() {
  testWidgets(
    'scope and citation content reflow in a narrow IME viewport at large text',
    (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(320, 640)
        ..devicePixelRatio = 1
        ..viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.reset);

      const String longTitle =
          'A synthetic source title that wraps across a narrow viewport';
      const String quote =
          'A synthetic source excerpt with enough words to wrap around a narrow '
          'screen while remaining readable above the keyboard.';
      final LocalNoteState note = ownedNote(title: longTitle, content: quote);
      final RagSource source = sourceFor(note, sourceId: 'S1', quote: quote);
      final RagPresentationHarness harness = RagPresentationHarness(
        local: localState(notes: <LocalNoteState>[note]),
      );
      await harness.grant();
      harness.gateway.queryScript.add(
        answeredResult(<RagSource>[source], answer: 'A synthetic answer.'),
      );
      await harness.service.ask(
        question: 'Which source supports this?',
        scope: const RagScope.account(),
      );

      await pumpRagPage(
        tester,
        harness,
        textScaler: const TextScaler.linear(2),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(RagPage.answerKey), findsOneWidget);
      expect(
        find.byKey(ValueKey<String>('rag-source-${source.sourceId}')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey<String>('rag-scope-account')))
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(find.text(longTitle), findsOneWidget);
      expect(find.text(quote), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unavailable query failure remains announced and readable at narrow width',
    (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(320, 640)
        ..devicePixelRatio = 1
        ..viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.reset);

      final RagPresentationHarness harness = RagPresentationHarness();
      await harness.grant();
      harness.gateway.queryScript.add(
        const RagFailure(RagFailureCode.providerUnavailable),
      );
      await pumpRagPage(
        tester,
        harness,
        textScaler: const TextScaler.linear(1.6),
      );

      final Finder field = find.byKey(RagPage.questionFieldKey);
      await tester.enterText(field, 'A synthetic question');
      await tester.ensureVisible(find.byKey(RagPage.askButtonKey));
      await tester.tap(find.byKey(RagPage.askButtonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(RagPage.failureKey), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('temporarily unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
