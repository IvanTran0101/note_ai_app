// Widget tests for the local-LLM debug screen.
//
// A fake summarizer is injected so no model, worker isolate, or FFI is
// involved. This replaces the Flutter starter counter test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/domain/note_intelligence/summary.dart';
import 'package:note_ai_app/presentation/debug/local_llm_debug_page.dart';

void main() {
  testWidgets('debug page shows the summary produced for the note', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LocalLlmDebugPage(
          summarize: (String content) async => Summary('Summary: $content'),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Note body here');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text('Summary: Note body here'), findsOneWidget);
  });

  testWidgets('debug page surfaces errors from the summarizer', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LocalLlmDebugPage(
          summarize: (String content) async =>
              throw StateError('model load failed'),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Note body here');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('model load failed'), findsOneWidget);
  });
}
