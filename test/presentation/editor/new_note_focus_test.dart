import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/editor/rich_note_editor.dart';
import 'package:note_ai_app/presentation/notes/note_detail_localizations.dart';
import 'package:note_ai_app/presentation/notes/note_detail_page.dart';

import 'note_detail_test_controller.dart';

void main() {
  testWidgets('embedded draft autosave keeps title focus and rich editor', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = RichTestNotesController();
    final detailKey = GlobalKey<NoteDetailPageState>();
    var dirtyNotifications = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          NoteDetailCopy.delegate,
          engine.AppFlowyEditorLocalizations.delegate,
        ],
        home: Scaffold(
          body: SizedBox.expand(
            child: StatefulBuilder(
              builder: (context, setParentState) => NoteDetailPage(
                key: detailKey,
                showAppBar: false,
                notesController: controller,
                onEmbeddedExit: (_) {},
                onDirtyChanged: (_) => setParentState(() {
                  dirtyNotifications++;
                }),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder titleFinder = find.byKey(NoteDetailPage.titleFieldKey);
    final FocusNode titleFocus = tester
        .widget<TextField>(titleFinder)
        .focusNode!;
    final Object editorStateBeforeSave = tester.state(
      find.byType(RichNoteEditor),
    );
    final detailStateBeforeSave = detailKey.currentState;

    await tester.tap(titleFinder);
    await tester.enterText(titleFinder, 'M09 Final UI21');
    expect(titleFocus.hasFocus, isTrue);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(controller.richSaves, 1);
    expect(controller.last?.title, 'M09 Final UI21');
    expect(dirtyNotifications, greaterThanOrEqualTo(2));
    expect(identical(detailStateBeforeSave, detailKey.currentState), isTrue);
    expect(titleFocus.hasFocus, isTrue);
    expect(
      identical(
        editorStateBeforeSave,
        tester.state(find.byType(RichNoteEditor)),
      ),
      isTrue,
      reason: 'first local save must not remount the rich editor',
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });
}
