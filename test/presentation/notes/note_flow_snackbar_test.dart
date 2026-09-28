import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/presentation/notes/note_flow_snackbar.dart';
import 'package:note_ai_app/presentation/notes/notes_theme_tokens.dart';

void main() {
  for (final Brightness brightness in Brightness.values) {
    testWidgets(
      'transient Notes feedback uses the $brightness floating toast and retains its action',
      (WidgetTester tester) async {
        tester.view
          ..physicalSize = const Size(390, 844)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final NoteFlowUiTokens tokens = brightness == Brightness.dark
            ? NoteFlowUiTokens.dark()
            : NoteFlowUiTokens.light();
        int actionCalls = 0;
        final SnackBarAction action = SnackBarAction(
          label: 'Undo',
          onPressed: () => actionCalls++,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness)
                .copyWith(extensions: <ThemeExtension<dynamic>>[tokens]),
            home: Builder(
              builder: (BuildContext context) => Scaffold(
                body: TextButton(
                  onPressed: () => ScaffoldMessenger.of(context)
                    ..showSnackBar(
                      buildNoteFlowSnackBar(
                        context: context,
                        message: 'Note deleted.',
                        action: action,
                      ),
                    ),
                  child: const Text('Show feedback'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show feedback'));
        await tester.pumpAndSettle();

        final SnackBar snackBar = tester.widget<SnackBar>(
          find.byType(SnackBar),
        );
        expect(snackBar.behavior, SnackBarBehavior.floating);
        expect(snackBar.backgroundColor, tokens.elevatedSurface);
        expect(identical(snackBar.action, action), isTrue);
        expect(find.text('Note deleted.'), findsOneWidget);
        expect(find.text('Undo'), findsOneWidget);

        final RoundedRectangleBorder shape =
            snackBar.shape! as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(NoteFlowRadius.card));
        expect(shape.side.color, tokens.divider);

        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(actionCalls, 1);
      },
    );
  }
}
