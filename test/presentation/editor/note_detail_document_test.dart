import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/rich_note_editor.dart';
import 'package:note_ai_app/presentation/editor/selection_formatting_controller.dart';
import 'package:note_ai_app/presentation/editor/nested_block_commands.dart';
import 'package:note_ai_app/presentation/editor/basic_block_commands.dart';
import 'package:note_ai_app/presentation/notes/note_detail_localizations.dart';
import 'package:note_ai_app/presentation/notes/note_detail_page.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';
import 'package:note_ai_app/presentation/notes/notes_workspace_page.dart';
import 'package:note_ai_app/presentation/notes/notes_localizations.dart';

void main() {
  testWidgets(
    'New note after autosave creates a fresh editor without the prior body',
    (tester) async {
      final controller = _RichController();
      final key = GlobalKey<NotesWorkspacePageState>();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            NotesCopy.delegate,
            NoteDetailCopy.delegate,
            engine.AppFlowyEditorLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: NotesWorkspacePage(key: key, controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      key.currentState!.startNewNote();
      await tester.pumpAndSettle();
      final first = tester
          .widget<RichNoteEditor>(find.byType(RichNoteEditor))
          .adapter;
      await tester.enterText(
        find.byKey(NoteDetailPage.titleFieldKey),
        'First created',
      );
      await first.editor.apply(
        first.editor.transaction..insertText(
          first.editor.document.root.children.first,
          0,
          'First body',
        ),
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(controller.last!.content, 'First body');
      key.currentState!.startNewNote();
      await tester.pumpAndSettle();
      final second = tester
          .widget<RichNoteEditor>(find.byType(RichNoteEditor))
          .adapter;
      expect(identical(first, second), false);
      expect(second.plainText, '');
      expect(
        tester
            .widget<TextField>(find.byKey(NoteDetailPage.titleFieldKey))
            .controller!
            .text,
        '',
      );
      expect(controller.last!.content, 'First body');
      await tester.pumpWidget(const SizedBox());
    },
  );
  final date = DateTime.utc(2026, 10, 15);
  NoteDto note({NoteDocument? document, int revision = 0}) => NoteDto(
    id: 'doc',
    ownerId: 'owner',
    title: 'Document',
    content: document?.plainText ?? 'AABB',
    document: document,
    contentRevision: revision,
    createdAt: date,
    updatedAt: date,
  );
  Future<void> pump(
    WidgetTester tester,
    _RichController controller,
    NoteDto? selected, {
    bool withRag = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          NoteDetailCopy.delegate,
          engine.AppFlowyEditorLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: NoteDetailPage(
          notesController: controller,
          note: selected,
          onOpenNoteRag: withRag ? (_) {} : null,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Enter uses upstream heading/list block rules; no unsupported slash handler',
    (tester) async {
      final document = NoteDocument([
        DocumentBlock(
          id: 'h4',
          kind: DocumentBlockKind.heading,
          level: 4,
          runs: const [DocumentText('Heading')],
        ),
      ]);
      await pump(tester, _RichController(), note(document: document));
      final host = tester.widget<RichNoteEditor>(find.byType(RichNoteEditor));
      final editorWidget = tester.widget<engine.AppFlowyEditor>(
        find.byType(engine.AppFlowyEditor),
      );
      expect(
        editorWidget.characterShortcutEvents.every((e) => e.character == '\n'),
        true,
      );
      expect(editorWidget.characterShortcutEvents, isNotEmpty);
      await tester.tap(find.byType(engine.AppFlowyRichText).first);
      await tester.pump();
      host.adapter.editor.selection = engine.Selection.collapsed(
        engine.Position(path: [0], offset: 7),
      );
      tester.testTextInput.enterText(' Heading\n');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(host.adapter.visibleDocument.blocks.map((b) => b.kind), [
        DocumentBlockKind.heading,
        DocumentBlockKind.paragraph,
      ]);
      expect(host.adapter.visibleDocument.blocks.first.id, 'h4');
      expect(host.adapter.visibleDocument.blocks.last.id, isNot('h4'));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'toggle child is editable and remains visible/selectable after heading conversion',
    (tester) async {
      final document = NoteDocument([
        DocumentBlock(
          id: 'toggle',
          kind: DocumentBlockKind.toggle,
          runs: const [DocumentText('Parent')],
        ),
      ]);
      await pump(tester, _RichController(), note(document: document));
      final adapter = tester
          .widget<RichNoteEditor>(find.byType(RichNoteEditor))
          .adapter;
      expect(
        await NestedBlockCommands(adapter)
            .addChild(adapter.editor.document.root.children.first),
        true,
      );
      await tester.pumpAndSettle();
      final child = adapter.editor.document.nodeAtPath([0, 0])!;
      await adapter.editor.apply(
        adapter.editor.transaction..insertText(child, 0, 'Nested content'),
      );
      await tester.pump();
      adapter.editor.selection = engine.Selection.collapsed(
        engine.Position(path: [0], offset: 0),
      );
      expect(
        await BasicBlockCommands(adapter)
            .choose(basicBlockChoices[4], adapter.capture(range: false)!),
        true,
      );
      await tester.pumpAndSettle();
      expect(adapter.plainText, 'Parent\nNested content');
      expect(find.byType(engine.AppFlowyRichText), findsNWidgets(2));
      final nodes = tester
          .widgetList<engine.AppFlowyRichText>(
            find.byType(engine.AppFlowyRichText),
          )
          .toList();
      expect(nodes.last.node.delta!.toPlainText(), 'Nested content');
      await tester.tap(find.byWidget(nodes.last));
      await tester.pump();
      expect(adapter.editor.selection!.start.path, [0, 0]);
      tester.testTextInput.enterText(' Nested edited');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        adapter.visibleDocument.blocks.single.children.single.plainText,
        'Nested edited',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'actual heading RichText keeps inline font size after both decorators',
    (tester) async {
      final document = NoteDocument([
        DocumentBlock(
          id: 'heading',
          kind: DocumentBlockKind.heading,
          level: 4,
          runs: [
            DocumentText('Painted range', marks: DocumentMarks(fontSize: 24)),
          ],
        ),
      ]);
      await pump(tester, _RichController(), note(document: document));
      final sizes = <double?>[];
      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        rich.text.visitChildren((span) {
          if (span is TextSpan && span.text == 'Painted range') {
            sizes.add(span.style?.fontSize);
          }
          return true;
        });
      }
      expect(sizes, contains(24.0));
      expect(sizes, isNot(contains(18.0)));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('pointer title focus routes typing to title instead of body', (
    tester,
  ) async {
    await pump(tester, _RichController(), note());
    final editor = tester.widget<RichNoteEditor>(find.byType(RichNoteEditor));
    await tester.tap(find.byType(engine.AppFlowyRichText).first);
    await tester.pump();
    await tester.tap(find.byKey(NoteDetailPage.titleFieldKey));
    await tester.pump();
    tester.testTextInput.enterText('Title through real focus');
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(NoteDetailPage.titleFieldKey))
          .controller!
          .text,
      'Title through real focus',
    );
    expect(editor.adapter.plainText, 'AABB');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'RAG availability never moves the rich editor during typing/save',
    (tester) async {
      await pump(tester, _RichController(), note(revision: 1), withRag: true);
      final host = tester.widget<RichNoteEditor>(find.byType(RichNoteEditor));
      final before = tester.getTopLeft(find.byType(RichNoteEditor));
      expect(find.byKey(NoteDetailPage.askNotesKey), findsOneWidget);
      await host.adapter.editor.apply(
        host.adapter.editor.transaction..insertText(
          host.adapter.editor.document.root.children.first,
          0,
          'X',
        ),
      );
      await tester.pump();
      expect(find.byKey(NoteDetailPage.askNotesKey), findsNothing);
      expect(tester.getTopLeft(find.byType(RichNoteEditor)), before);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(tester.getTopLeft(find.byType(RichNoteEditor)), before);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'keyboard input edits the production document through upstream IME',
    (tester) async {
      final controller = _RichController();
      await pump(tester, controller, note());
      final adapter = tester
          .widget<RichNoteEditor>(find.byType(RichNoteEditor))
          .adapter;
      await tester.tap(find.byType(engine.AppFlowyRichText).first);
      await tester.pump();
      expect(adapter.editor.selection, isNotNull);
      expect(tester.testTextInput.isRegistered, true);
      tester.testTextInput.enterText(' Typed Việt 📝');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(adapter.plainText, 'Typed Việt 📝');
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(controller.last!.content, 'Typed Việt 📝');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'selection does not save; format-only local autosave retains the document',
    (tester) async {
      final controller = _RichController();
      await pump(tester, controller, note());
      final adapter = tester
          .widget<RichNoteEditor>(find.byType(RichNoteEditor))
          .adapter;
      expect(adapter.document, null);
      adapter.editor.selection = engine.Selection.single(
        path: [0],
        startOffset: 2,
        endOffset: 4,
      );
      await tester.pump(const Duration(seconds: 4));
      expect(controller.richSaves, 0);
      expect(controller.plainSaves, 0);
      expect(
        await SelectionFormattingController(adapter)
            .size(adapter.capture()!, 24),
        true,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(controller.richSaves, 1);
      expect(controller.plainSaves, 0);
      expect(controller.last!.content, 'AABB');
      expect(
        controller.last!.document!.blocks.single.runs.last.marks.fontSize,
        24,
      );
      final selected = adapter.editor.selection;
      await pump(tester, controller, controller.last);
      final acknowledged = tester
          .widget<RichNoteEditor>(find.byType(RichNoteEditor))
          .adapter;
      expect(identical(acknowledged, adapter), true);
      expect(acknowledged.editor.selection, selected);
      expect(acknowledged.editor.undoManager.undoStack.isNonEmpty, true);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'title-only legacy save does not inflate body; rich title-only preserves format',
    (tester) async {
      final controller = _RichController();
      await pump(tester, controller, note());
      await tester.enterText(
        find.byKey(NoteDetailPage.titleFieldKey),
        'New title',
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(controller.plainSaves, 1);
      expect(controller.last!.document, null);
      await tester.pumpWidget(const SizedBox());
      final rich = NoteDocument([
        DocumentBlock(
          id: 'p',
          kind: DocumentBlockKind.paragraph,
          runs: [DocumentText('AABB', marks: DocumentMarks(bold: true))],
        ),
      ]);
      await pump(tester, controller, note(document: rich));
      await tester.enterText(
        find.byKey(NoteDetailPage.titleFieldKey),
        'Rich title',
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(controller.richSaves, 1);
      expect(controller.last!.document, rich);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'new rich note remains clean on open; title-only creates empty typed document',
    (tester) async {
      final controller = _RichController();
      await pump(tester, controller, null);
      await tester.pump(const Duration(seconds: 4));
      expect(controller.richSaves, 0);
      await tester.enterText(
        find.byKey(NoteDetailPage.titleFieldKey),
        'Empty typed note',
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(controller.richSaves, 1);
      expect(controller.last!.document!.blocks, isEmpty);
      expect(controller.last!.content, '');
      await tester.pumpWidget(const SizedBox());
    },
  );
}

final class _RichController
    implements
        NotesApplicationController,
        DocumentNotesController,
        SnapshotNotesController {
  int richSaves = 0, plainSaves = 0;
  NoteDto? last;
  @override
  Future<List<NoteDto>> listNotes() async => last == null ? [] : [last!];
  @override
  get summaryConsent => null;
  NoteDto saved(
    NoteDto? previous,
    String title,
    String content,
    NoteDocument? document,
  ) => last = NoteDto(
    id: previous?.id ?? 'new',
    ownerId: previous?.ownerId ?? 'owner',
    title: title,
    content: content,
    document: document,
    createdAt: previous?.createdAt ?? DateTime.utc(2026),
    updatedAt: DateTime.utc(2026, 10, 15),
  );
  @override
  Future<NoteDto> saveDocumentSnapshot(
    NoteDto selected,
    String title,
    NoteDocument document,
  ) async {
    richSaves++;
    return saved(selected, title, document.plainText, document);
  }

  @override
  Future<NoteDto> createDocumentNote({
    required String title,
    required NoteDocument document,
  }) async {
    richSaves++;
    return saved(null, title, document.plainText, document);
  }

  @override
  Future<NoteDto> saveEditorSnapshot(
    NoteDto selected,
    String title,
    String content,
  ) async {
    plainSaves++;
    return saved(selected, title, content, null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
