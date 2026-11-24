import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/notes/attachment_document_controls.dart';

void main() {
  for (final state in [
    (1, 3, false),
    (2, 3, false),
    (3, 3, false),
    (1, 0, false),
    (2, 3, true),
  ]) {
    testWidgets(
      'PDF navigation page${state.$1}/pages${state.$2}/busy${state.$3}',
      (tester) async {
        final changes = <int>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AttachmentDocumentControls(
                page: state.$1,
                pages: state.$2,
                busy: state.$3,
                onPage: changes.add,
              ),
            ),
          ),
        );
      final previous = find.widgetWithIcon(IconButton, Icons.chevron_left),
          next = find.widgetWithIcon(IconButton, Icons.chevron_right);
        expect(
          tester.widget<IconButton>(previous).onPressed != null,
          !state.$3 && state.$1 > 1,
        );
        expect(
          tester.widget<IconButton>(next).onPressed != null,
          !state.$3 && state.$2 > 0 && state.$1 < state.$2,
        );
        expect(
          find.text(
            state.$2 == 0 ? 'Loading PDF…' : 'Page ${state.$1} / ${state.$2}',
          ),
          findsOneWidget,
        );
        await tester.tap(previous);
        await tester.tap(next);
        expect(changes, [
          if (!state.$3 && state.$1 > 1) state.$1 - 1,
          if (!state.$3 && state.$2 > 0 && state.$1 < state.$2) state.$1 + 1,
        ]);
      },
    );
  }
}
