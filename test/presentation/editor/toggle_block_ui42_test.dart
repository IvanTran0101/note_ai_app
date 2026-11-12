import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/editor_shortcuts.dart';
import 'package:note_ai_app/presentation/editor/rich_note_editor.dart';
import 'package:note_ai_app/presentation/editor/slash_command_controller.dart';
import 'package:note_ai_app/presentation/notes/note_detail_localizations.dart';
import 'package:note_ai_app/presentation/notes/note_detail_page.dart';
import 'package:note_ai_app/presentation/notes/notes_localizations.dart';

import 'note_detail_test_controller.dart';

void main() {
  final date = DateTime.utc(2026, 10, 23);

  NoteDto note(NoteDocument document) => NoteDto(
    id: 'toggle-ui42',
    ownerId: 'owner',
    title: 'Toggle UI42',
    content: document.plainText,
    document: document,
    createdAt: date,
    updatedAt: date,
  );

  Future<void> pumpNote(WidgetTester tester, NoteDocument document) async {
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
        home: NoteDetailPage(
          notesController: RichTestNotesController(),
          note: note(document),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  DocumentBlock toggle({List<DocumentBlock> children = const []}) =>
      DocumentBlock(
        id: 'toggle',
        kind: DocumentBlockKind.toggle,
        runs: [DocumentText('Parent')],
        children: children,
      );

  testWidgets('new empty toggle follows the collapsed Notion flow', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpNote(tester, NoteDocument([toggle()]));
    final adapter = tester
        .widget<RichNoteEditor>(find.byType(RichNoteEditor))
        .adapter;
    final disclosure = find.byKey(
      const ValueKey('m09-toggle-disclosure-toggle'),
    );
    final row = find.byKey(const ValueKey('m09-toggle-row-toggle'));
    final title = find.byType(engine.AppFlowyRichText).first;

    expect(adapter.expandedToggles['toggle'], false);
    expect(tester.getSize(disclosure), Size(24, kIsWeb ? 24 : 48));
    expect(tester.getSize(row).height, kIsWeb ? 24 : 48);
    expect(
      tester.getTopLeft(title).dx - tester.getTopLeft(row).dx,
      closeTo(kIsWeb ? 32 : 24, 0.1),
    );
    expect(
      tester.getRect(disclosure).right,
      lessThanOrEqualTo(tester.getTopLeft(title).dx),
    );
    expect(tester.getSemantics(disclosure).label, 'Expand toggle');
    expect(find.text('Empty toggle. Click to add a block.'), findsNothing);
    expect(find.text('Add nested block'), findsNothing);
    final beforeExpansion = adapter.document;
    final beforeRevision = adapter.revision;

    final disclosureRect = tester.getRect(disclosure);
    await tester.tapAt(
      Offset(disclosureRect.right - .5, disclosureRect.center.dy),
    );
    await tester.pumpAndSettle();
    expect(adapter.expandedToggles['toggle'], true);
    expect(adapter.document, beforeExpansion);
    expect(adapter.revision, beforeRevision);
    expect(find.text('Empty toggle. Click to add a block.'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Empty toggle. Click to add a block.')).dx -
          tester.getTopLeft(row).dx,
      closeTo(kIsWeb ? 32 : 24, 0.1),
    );

    await tester.tap(find.byKey(const ValueKey('m09-toggle-empty-toggle')));
    await tester.pumpAndSettle();
    expect(adapter.editor.document.nodeAtPath([0, 0])?.type, 'paragraph');
    expect(adapter.editor.selection?.start.path, [0, 0]);
    expect(find.text('Empty toggle. Click to add a block.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('wrapped large toggle title grows above its child', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final document = NoteDocument([
      DocumentBlock(
        id: 'toggle',
        kind: DocumentBlockKind.toggle,
        runs: [
          DocumentText(
            'Large toggle title wraps naturally and keeps every nested child below the final line on a narrow screen',
            marks: DocumentMarks(fontSize: 48),
          ),
        ],
        children: [
          DocumentBlock(
            id: 'large-title-child',
            kind: DocumentBlockKind.paragraph,
            runs: [DocumentText('Child below the complete title')],
          ),
        ],
      ),
    ]);
    await pumpNote(tester, document);

    final row = find.byKey(const ValueKey('m09-toggle-row-toggle'));
    final disclosure = find.byKey(
      const ValueKey('m09-toggle-disclosure-toggle'),
    );
    final richText = find.byType(engine.AppFlowyRichText);
    final title = richText.at(0);
    final child = richText.at(1);
    final titleHeight = tester.getSize(title).height;
    final rowRect = tester.getRect(row);

    final adapter = tester
        .widget<RichNoteEditor>(find.byType(RichNoteEditor))
        .adapter;
    final engineNode = adapter.editor.document.nodeAtPath([0])!;
    final selectable = engineNode.selectable!;
    final cursor = selectable.getCursorRectInPosition(
      engine.Position(path: [0], offset: 0),
    )!;
    final engineCursorCenter = selectable.localToGlobal(cursor.center);

    expect(titleHeight, greaterThan(72));
    expect(rowRect.height, greaterThan(titleHeight - 1));
    expect(tester.getTopLeft(child).dy, greaterThanOrEqualTo(rowRect.bottom));
    expect(tester.getSize(disclosure).height, greaterThanOrEqualTo(48));
    final iconRect = tester.getRect(find.byIcon(Icons.play_arrow));
    expect(iconRect.center.dy, closeTo(engineCursorCenter.dy, 1));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'toggle glyph follows engine cursor zero with mixed inline sizes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final document = NoteDocument([
        DocumentBlock(
          id: 'toggle',
          kind: DocumentBlockKind.toggle,
          runs: [
            DocumentText('A '),
            DocumentText('BIG', marks: DocumentMarks(fontSize: 48)),
          ],
          children: [
            DocumentBlock(
              id: 'mixed-size-child',
              kind: DocumentBlockKind.paragraph,
              runs: [DocumentText('Nested content')],
            ),
          ],
        ),
      ]);
      await pumpNote(tester, document);

      final adapter = tester
          .widget<RichNoteEditor>(find.byType(RichNoteEditor))
          .adapter;
      final node = adapter.editor.document.nodeAtPath([0])!;
      final selectable = node.selectable!;
      final cursor = selectable.getCursorRectInPosition(
        engine.Position(path: [0], offset: 0),
      )!;
      final engineCursorCenter = selectable.localToGlobal(cursor.center);
      final title = find.byType(engine.AppFlowyRichText).first;
      final row = find.byKey(const ValueKey('m09-toggle-row-toggle'));
      final icon = tester.getRect(find.byIcon(Icons.play_arrow));

      expect(tester.getSize(title).height, lessThan(100));
      expect(icon.center.dy, closeTo(engineCursorCenter.dy, 1));
      expect(
        tester.getTopLeft(title).dx - tester.getTopLeft(row).dx,
        closeTo(kIsWeb ? 32 : 24, 0.1),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('existing toggle children stay visible on editor reopen', (
    tester,
  ) async {
    final document = NoteDocument([
      toggle(
        children: [
          DocumentBlock(
            id: 'existing-child',
            kind: DocumentBlockKind.paragraph,
            runs: [DocumentText('Existing child')],
          ),
        ],
      ),
    ]);
    await pumpNote(tester, document);
    final adapter = tester
        .widget<RichNoteEditor>(find.byType(RichNoteEditor))
        .adapter;

    expect(adapter.expandedToggles['toggle'], true);
    expect(find.byType(engine.AppFlowyRichText), findsNWidgets(2));
    expect(find.text('Add nested block'), findsNothing);
    final parentTitle = find.byType(engine.AppFlowyRichText).at(0);
    final childText = find.byType(engine.AppFlowyRichText).at(1);
    expect(
      tester.getTopLeft(childText).dx - tester.getTopLeft(parentTitle).dx,
      closeTo(0, 0.1),
    );
    adapter.editor.selection = engine.Selection.collapsed(
      engine.Position(path: [0, 0], offset: 2),
    );
    await tester.pumpAndSettle();
    final beforeCollapse = adapter.document;
    await tester.tap(
      find.byKey(const ValueKey('m09-toggle-disclosure-toggle')),
    );
    await tester.pumpAndSettle();
    expect(adapter.expandedToggles['toggle'], false);
    expect(adapter.editor.selection?.start.path, [0]);
    expect(adapter.document, beforeCollapse);
    expect(find.byType(engine.AppFlowyRichText), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Enter at toggle title end inserts a child before existing ones',
    (tester) async {
      final document = NoteDocument([
        toggle(
          children: [
            DocumentBlock(
              id: 'existing-child',
              kind: DocumentBlockKind.paragraph,
              runs: [DocumentText('Existing child')],
            ),
          ],
        ),
      ]);
      await pumpNote(tester, document);
      final adapter = tester
          .widget<RichNoteEditor>(find.byType(RichNoteEditor))
          .adapter;
      final slash = SlashCommandController(adapter);
      addTearDown(slash.dispose);
      adapter.editor.selection = engine.Selection.collapsed(
        engine.Position(path: [0], offset: 6),
      );
      final enter = richEditorShortcuts(
        adapter,
        slash,
      ).singleWhere((event) => event.key == 'm09 enter');

      expect(enter.handler(adapter.editor), KeyEventResult.handled);
      await tester.pumpAndSettle();
      final children = adapter.document!.blocks.single.children;
      expect(children, hasLength(2));
      expect(children.first.plainText, isEmpty);
      expect(children.last.plainText, 'Existing child');
      expect(adapter.editor.selection?.start.path, [0, 0]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Enter inside toggle title is left to normal text editing', (
    tester,
  ) async {
    await pumpNote(tester, NoteDocument([toggle()]));
    final adapter = tester
        .widget<RichNoteEditor>(find.byType(RichNoteEditor))
        .adapter;
    final slash = SlashCommandController(adapter);
    addTearDown(slash.dispose);
    adapter.editor.selection = engine.Selection.collapsed(
      engine.Position(path: [0], offset: 2),
    );
    final enter = richEditorShortcuts(
      adapter,
      slash,
    ).singleWhere((event) => event.key == 'm09 enter');

    expect(enter.handler(adapter.editor), KeyEventResult.ignored);
    expect(adapter.document!.blocks.single.children, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
