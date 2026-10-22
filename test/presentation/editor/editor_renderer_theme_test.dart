import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';
import 'package:note_ai_app/presentation/editor/rich_note_editor.dart';

void main() {
  testWidgets('theme rebuild refreshes quote renderer and retains selection', (
    tester,
  ) async {
    const lightScheme = ColorScheme.light(
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF202020),
    );
    const darkScheme = ColorScheme.dark(
      surface: Color(0xFF101010),
      onSurface: Color(0xFFF0F0F0),
    );
    final focus = FocusNode();
    final adapter = RichEditorAdapter(
      document: NoteDocument([
        DocumentBlock(
          id: 'quote',
          kind: DocumentBlockKind.quote,
          runs: const [DocumentText('Theme quote')],
        ),
      ]),
      legacyText: '',
      canEdit: () => true,
      isLive: () => true,
      accessGeneration: () => 1,
      onChanged: () {},
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
      focus.dispose();
    });

    Future<void> pumpEditor(ColorScheme scheme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: scheme),
          localizationsDelegates: const [
            engine.AppFlowyEditorLocalizations.delegate,
          ],
          home: Scaffold(
            body: RichNoteEditor(
              adapter: adapter,
              focusNode: focus,
              header: const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpEditor(lightScheme);

    final editorState = adapter.editor;
    final quoteNode = editorState.document.root.children.single;
    final quoteKey = quoteNode.key;
    editorState.service.selectionService.updateSelection(
      engine.Selection.collapsed(engine.Position(path: [0], offset: 4)),
    );
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    final keyboardService = editorState.service.keyboardService;
    expect(keyboardService, isNotNull);

    final quoteFinder = find.byType(engine.QuoteBlockComponentWidget);
    final quoteMarkerFinder = find.descendant(
      of: quoteFinder,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is SizedBox &&
            widget.width == 3 &&
            widget.child is ColoredBox,
      ),
    );
    final markerFinder = find.descendant(
      of: quoteMarkerFinder,
      matching: find.byType(ColoredBox),
    );
    expect(quoteMarkerFinder, findsOneWidget);
    expect(markerFinder, findsOneWidget);
    expect(
      tester.widget<ColoredBox>(markerFinder).color,
      lightScheme.onSurface,
    );

    await pumpEditor(darkScheme);

    expect(markerFinder, findsOneWidget);
    expect(tester.widget<ColoredBox>(markerFinder).color, darkScheme.onSurface);
    expect(adapter.editor, same(editorState));
    expect(editorState.document.root.children.single, same(quoteNode));
    expect(quoteNode.key, same(quoteKey));
    expect(editorState.selection?.start.path, [0]);
    expect(editorState.selection?.start.offset, 4);
    expect(editorState.service.keyboardService, same(keyboardService));
    expect(focus.hasFocus, isTrue);
  });
}
