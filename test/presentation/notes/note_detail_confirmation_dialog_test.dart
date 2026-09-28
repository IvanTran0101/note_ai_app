import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/presentation/notes/note_detail_back_confirmation.dart';
import 'package:note_ai_app/presentation/notes/note_detail_delete_confirmation.dart';
import 'package:note_ai_app/presentation/notes/note_detail_localizations.dart';
import 'package:note_ai_app/presentation/notes/notes_theme_tokens.dart';

void main() {
  for (final Brightness brightness in Brightness.values) {
    testWidgets(
      'confirmation dialogs use the $brightness palette and fit above the keyboard',
      (WidgetTester tester) async {
        tester.view
          ..physicalSize = const Size(360, 640)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final NoteFlowUiTokens tokens = brightness == Brightness.dark
            ? NoteFlowUiTokens.dark()
            : NoteFlowUiTokens.light();
        const Key deleteTriggerKey = ValueKey<String>('open-delete-dialog');
        const Key backTriggerKey = ValueKey<String>('open-back-dialog');
        const Key deleteConfirmKey = ValueKey<String>('confirm-delete');

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness)
                .copyWith(extensions: <ThemeExtension<dynamic>>[tokens]),
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              NoteDetailCopy.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
            builder: (BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                viewInsets: const EdgeInsets.only(bottom: 220),
                viewPadding: const EdgeInsets.only(top: 24, bottom: 24),
              ),
              child: child!,
            ),
            home: Builder(
              builder: (BuildContext context) {
                final NoteDetailCopy copy = NoteDetailCopy.of(context);
                return Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        TextButton(
                          key: deleteTriggerKey,
                          onPressed: () => showNoteDetailDeleteConfirmation(
                            context: context,
                            copy: copy,
                            confirmKey: deleteConfirmKey,
                          ),
                          child: const Text('Open delete dialog'),
                        ),
                        TextButton(
                          key: backTriggerKey,
                          onPressed: () => showNoteDetailBackConfirmation(
                            context: context,
                            copy: copy,
                          ),
                          child: const Text('Open back dialog'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );

        Future<void> expectNoteFlowDialog() async {
          final AlertDialog dialog = tester.widget<AlertDialog>(
            find.byType(AlertDialog),
          );
          expect(dialog.backgroundColor, tokens.elevatedSurface);
          expect(dialog.surfaceTintColor, Colors.transparent);
          expect(dialog.titleTextStyle?.color, tokens.textPrimary);
          expect(dialog.contentTextStyle?.color, tokens.textSecondary);
          final RoundedRectangleBorder shape =
              dialog.shape! as RoundedRectangleBorder;
          expect(
            shape.borderRadius,
            BorderRadius.circular(NoteFlowRadius.dialog),
          );
          expect(shape.side.color, tokens.divider);

          final Finder dialogSurface = find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(Material),
              )
              .first;
          final Rect rect = tester.getRect(dialogSurface);
          expect(rect.left, greaterThanOrEqualTo(NoteFlowSpacing.xl));
          expect(rect.right, lessThanOrEqualTo(360 - NoteFlowSpacing.xl));
          expect(rect.bottom, lessThanOrEqualTo(640 - 220));
          expect(tester.takeException(), isNull);
        }

        await tester.tap(find.byKey(deleteTriggerKey));
        await tester.pumpAndSettle();
        await expectNoteFlowDialog();
        expect(find.byKey(deleteConfirmKey), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(backTriggerKey));
        await tester.pumpAndSettle();
        await expectNoteFlowDialog();
        expect(
          find.byKey(const ValueKey<String>('note-detail-back-save')),
          findsOneWidget,
        );
      },
    );
  }
}
