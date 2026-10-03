import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/presentation/notes/animated_note_list.dart';
import 'package:note_ai_app/presentation/notes/note_detail_localizations.dart';
import 'package:note_ai_app/presentation/notes/note_detail_editor_form.dart';
import 'package:note_ai_app/presentation/notes/note_detail_summary.dart';

void main() {
  NoteDto note(String id) => NoteDto(
    id: id,
    ownerId: 'owner',
    title: id,
    content: 'Body $id',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  testWidgets(
    'list insertion, reorder and removal keep only current rows actionable',
    (WidgetTester tester) async {
      int selected = 0;
      Widget list(List<NoteDto> notes) => MaterialApp(
        home: Scaffold(
          body: AnimatedNoteList(
            notes: notes,
            selectedNoteId: null,
            actionBusy: false,
            onSelectNote: (_) => selected++,
          ),
        ),
      );
      await tester.pumpWidget(list(<NoteDto>[note('a'), note('b')]));
      await tester.pumpWidget(list(<NoteDto>[note('c'), note('b'), note('a')]));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(list(<NoteDto>[note('a'), note('c')]));
      final Finder outgoing = find.byKey(
        const ValueKey<String>('outgoing-note-a'),
      );
      expect(outgoing, findsOneWidget);
      expect(tester.widget<ListTile>(outgoing).onTap, isNull);
      await tester.pumpAndSettle();
      final Finder a = find.byKey(const ValueKey<String>('note-a'));
      final Finder c = find.byKey(const ValueKey<String>('note-c'));
      expect(tester.getTopLeft(a).dy, lessThan(tester.getTopLeft(c).dy));
      expect(find.byKey(const ValueKey<String>('note-b')), findsNothing);
      await tester.tap(a);
      expect(selected, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduce motion displays the complete summary immediately', (
    WidgetTester tester,
  ) async {
    const String text = 'The complete summary is available immediately.';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Scaffold(
              body: NoteDetailSummary(
                copy: NoteDetailCopy.of(context),
                hasSavedNote: true,
                summary: text,
                isStale: false,
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<SelectableText>(
            find.byKey(const ValueKey<String>('note-detail-summary-text')),
          )
          .data,
      text,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduce motion keeps note content readable while summarizing', (
    WidgetTester tester,
  ) async {
    final TextEditingController title = TextEditingController(text: 'Title');
    final TextEditingController content = TextEditingController(
      text: 'Readable note',
    );
    final FocusNode focus = FocusNode();
    addTearDown(title.dispose);
    addTearDown(content.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Scaffold(
              body: NoteDetailEditorForm(
                titleController: title,
                contentController: content,
                contentFocusNode: focus,
                contentFieldContextKey: GlobalKey(),
                copy: NoteDetailCopy.of(context),
                hasSavedNote: true,
                isDirty: false,
                error: null,
                statusMessage: null,
                actionBusy: true,
                isSummarizing: true,
                showBusyIndicator: false,
                provisioningReader: null,
                onProvisioningRetry: null,
                onProvisioningCancel: null,
                summary: null,
                summaryStale: false,
              ),
            ),
          ),
        ),
      ),
    );
    final TextField field = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('note-detail-content-field')),
    );
    expect(field.style!.color, isNot(Colors.transparent));
    expect(field.controller!.text, 'Readable note');
    expect(tester.takeException(), isNull);
  });
}
