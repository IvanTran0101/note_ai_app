import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/presentation/notes/note_detail_action_bar.dart';

void main() {
  Widget buildBar({
    bool isSaving = false,
    bool isSummarizing = false,
    bool canSave = true,
    bool canSummarize = true,
    VoidCallback? onSave,
    VoidCallback? onSummarize,
    VoidCallback? onMore,
  }) {
    return MaterialApp(
      home: Scaffold(
        bottomNavigationBar: NoteDetailActionBar(
          isSaving: isSaving,
          isSummarizing: isSummarizing,
          canSave: canSave,
          canSummarize: canSummarize,
          onSave: onSave ?? () {},
          onSummarize: onSummarize ?? () {},
          onMore: onMore,
          saveLabel: 'Save',
          summarizeLabel: 'Summarize',
          moreLabel: 'More',
          savingLabel: 'Saving…',
          summarizingLabel: 'Summarizing…',
        ),
      ),
    );
  }

  testWidgets('exposes callbacks and stable action keys', (
    WidgetTester tester,
  ) async {
    int saves = 0;
    int summaries = 0;
    int more = 0;
    await tester.pumpWidget(
      buildBar(
        onSave: () => saves++,
        onSummarize: () => summaries++,
        onMore: () => more++,
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('note-detail-save')));
    await tester.tap(
      find.byKey(const ValueKey<String>('note-detail-summarize')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('note-detail-more')));

    expect(saves, 1);
    expect(summaries, 1);
    expect(more, 1);
  });

  testWidgets('disables actions and replaces labels while busy', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildBar(isSaving: true, isSummarizing: false, onMore: () {}),
    );

    expect(find.text('Saving…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('note-detail-save')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('note-detail-summarize')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey<String>('note-detail-more')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'keeps actions at least 48dp tall at phone sizes and large text',
    (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(320, 568)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: buildBar(onMore: () {}),
        ),
      );

      expect(
        tester
            .getSize(find.byKey(const ValueKey<String>('note-detail-save')))
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey<String>('note-detail-summarize')),
            )
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('remains visible above a simulated keyboard inset', (
    WidgetTester tester,
  ) async {
    tester.view
      ..physicalSize = const Size(320, 568)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(viewInsets: EdgeInsets.only(bottom: 220)),
        child: buildBar(onMore: () {}),
      ),
    );
    await tester.pumpAndSettle();

    final double actionBottom = tester
        .getRect(find.byKey(const ValueKey<String>('note-detail-save')))
        .bottom;
    expect(actionBottom, lessThanOrEqualTo(568 - 220));
    expect(tester.takeException(), isNull);
  });
}
