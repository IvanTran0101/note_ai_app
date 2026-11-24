import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';
import 'package:note_ai_app/presentation/editor/selection_toolbar.dart';
import 'package:note_ai_app/presentation/editor/selection_toolbar_layout.dart';

void main() {
  RichEditorAdapter selectedAdapter() {
    final adapter = RichEditorAdapter(
      document: null,
      legacyText: 'selected text',
      canEdit: () => true,
      isLive: () => true,
      accessGeneration: () => 1,
      onChanged: () {},
    );
    adapter.editor.selection = engine.Selection(
      start: engine.Position(path: [0], offset: 0),
      end: engine.Position(path: [0], offset: 8),
    );
    return adapter;
  }

  Widget app(
    RichEditorAdapter adapter, {
    double textScale = 1,
    EdgeInsets viewInsets = EdgeInsets.zero,
  }) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        viewInsets: viewInsets,
      ),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: SelectionToolbar(
            adapter: adapter,
            dialogContext: context,
            onPopupOpen: () {},
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'Web selection bubble follows the three-row format hierarchy',
    skip: !kIsWeb,
    (tester) async {
      tester.view
        ..physicalSize = const Size(1280, 720)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final adapter = selectedAdapter();
      addTearDown(adapter.dispose);

      await tester.pumpWidget(app(adapter));
      await tester.pumpAndSettle();

      final layout = find.byType(SelectionToolbarLayout);
      expect(tester.getSize(layout), const Size(192, 110));
      expect(find.text('Normal Text'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.byIcon(Icons.text_fields), findsNothing);
      expect(find.text('16 pt'), findsOneWidget);
      expect(find.text('√x'), findsOneWidget);
      for (final icon in [
        Icons.format_color_text,
        Icons.format_bold,
        Icons.format_italic,
        Icons.format_underlined,
        Icons.format_clear,
        Icons.link,
        Icons.format_strikethrough,
        Icons.code,
        Icons.more_horiz,
      ]) {
        expect(find.byIcon(icon), findsOneWidget);
      }

      final styleY = tester.getCenter(find.text('Normal Text')).dy;
      final colorY = tester.getCenter(find.byIcon(Icons.format_color_text)).dy;
      final clearY = tester.getCenter(find.byIcon(Icons.format_clear)).dy;
      final sizeY = tester.getCenter(find.text('16 pt')).dy;
      final linkY = tester.getCenter(find.byIcon(Icons.link)).dy;
      final strikeY = tester
          .getCenter(find.byIcon(Icons.format_strikethrough))
          .dy;
      final codeY = tester.getCenter(find.byIcon(Icons.code)).dy;
      final equationY = tester.getCenter(find.text('√x')).dy;
      final moreY = tester.getCenter(find.byIcon(Icons.more_horiz)).dy;
      expect(styleY, lessThan(colorY));
      expect(colorY, closeTo(clearY, 1));
      expect(clearY, closeTo(sizeY, 1));
      expect(sizeY, lessThan(linkY));
      expect(linkY, closeTo(strikeY, 1));
      expect(strikeY, closeTo(codeY, 1));
      expect(codeY, closeTo(equationY, 1));
      expect(linkY, closeTo(moreY, 1));
      expect(tester.takeException(), isNull);

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      expect(find.text('Highlight'), findsOneWidget);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('16 pt'));
      await tester.pumpAndSettle();
      final sizeDialog = find.byType(SimpleDialog);
      expect(sizeDialog, findsOneWidget);
      for (final size in [12, 14, 16, 18, 24, 32]) {
        expect(
          find.descendant(of: sizeDialog, matching: find.text('$size pt')),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(
          of: sizeDialog,
          matching: find.text('Custom size (12–48)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sizeDialog, matching: find.text('Reset size')),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('color chooser scrolls at large text scale with an IME inset', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final adapter = selectedAdapter();
    addTearDown(adapter.dispose);

    await tester.pumpWidget(
      app(
        adapter,
        textScale: 2,
        viewInsets: const EdgeInsets.only(bottom: 280),
      ),
    );
    await tester.pumpAndSettle();

    if (!kIsWeb) {
      expect(tester.getSize(find.byType(SelectionToolbarLayout)).height, 48);
      final boldButton = find.ancestor(
        of: find.byIcon(Icons.format_bold),
        matching: find.byType(IconButton),
      );
      expect(tester.getSize(boldButton), const Size(48, 48));
    }

    final colorButton = find.byTooltip('Text color');
    await tester.ensureVisible(colorButton);
    await tester.tap(colorButton);
    await tester.pumpAndSettle();

    expect(find.byType(SimpleDialog), findsOneWidget);
    final lastColor = find.text(DocumentColor.red.name);
    await tester.ensureVisible(lastColor);
    await tester.pumpAndSettle();
    expect(lastColor, findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(lastColor);
    await tester.pumpAndSettle();
    expect(
      adapter.document!.blocks.single.runs.first,
      DocumentText('selected', marks: DocumentMarks(color: DocumentColor.red)),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
