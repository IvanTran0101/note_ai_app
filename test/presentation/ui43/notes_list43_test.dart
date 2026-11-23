import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_dto.dart';
import 'package:note_ai_app/presentation/notes/animated_note_list.dart';
import 'package:note_ai_app/presentation/notes/notes_list_panel.dart';
import 'package:note_ai_app/presentation/notes/notes_theme_tokens.dart';

void main() {
  testWidgets(
    'narrow scaled Notes header and query remain scrollable with actions intact',
    (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(360, 480)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final DateTime now = DateTime.utc(2026, 10, 26);
      final NoteDto note = NoteDto(
        id: 'ui43-note',
        ownerId: 'owner',
        title: 'A long synthetic note title for the scaled list row',
        content: 'A readable synthetic preview for this Notes list row.',
        createdAt: now,
        updatedAt: now,
      );
      const String firstFilter = 'Synthetic filter option 1 with readable text';
      int newNotes = 0;
      int selectedNotes = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: <ThemeExtension<dynamic>>[NoteFlowUiTokens.light()],
          ),
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: NotesListPanel(
              notes: <NoteDto>[note],
              selectedNoteId: note.reference,
              error: null,
              actionBusy: false,
              queryEnabled: false,
              titleOverride:
                  'A long Notes heading that wraps at narrow text scales',
              queryControls: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const TextField(
                    key: ValueKey<String>('ui43-query-field'),
                    decoration: InputDecoration(labelText: 'Search notes'),
                  ),
                  for (int index = 0; index < 12; index++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        index == 0
                            ? firstFilter
                            : 'Synthetic filter option ${index + 1} with readable text',
                      ),
                    ),
                ],
              ),
              onNewNote: () => newNotes++,
              onSelectNote: (_) => selectedNotes++,
              onRetry: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final Finder queryScroll = find.byKey(
        const ValueKey<String>('notes-query-controls-scroll'),
      );
      expect(queryScroll, findsOneWidget);
      expect(
        tester.widget<SingleChildScrollView>(queryScroll).primary,
        isFalse,
      );
      final Finder firstFilterFinder = find.text(firstFilter);
      final double firstFilterTop = tester.getTopLeft(firstFilterFinder).dy;
      await tester.drag(queryScroll, const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(firstFilterFinder).dy, lessThan(firstFilterTop));
      expect(tester.getSize(find.byType(ListTile)).height, greaterThan(0));

      await tester.tap(find.byKey(const ValueKey<String>('new-note')));
      expect(newNotes, 1);
      await tester.tap(find.byType(ListTile));
      expect(selectedNotes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selected and hovered rows use quiet semantic surfaces', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime.utc(2026, 10, 26);
    final NoteDto note = NoteDto(
      id: 'ui43-row',
      ownerId: 'owner',
      title: 'Selected note',
      content: 'Preview text',
      createdAt: now,
      updatedAt: now,
    );
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.light();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: <ThemeExtension<dynamic>>[tokens],
        ),
        home: Scaffold(
          body: AnimatedNoteList(
            notes: <NoteDto>[note],
            selectedNoteId: note.reference,
            actionBusy: false,
            onSelectNote: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final ListTile tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.selected, isTrue);
    expect(tile.selectedTileColor, tokens.selectedSurface);
    expect(tile.hoverColor, tokens.subtleSurface);
  });
}
