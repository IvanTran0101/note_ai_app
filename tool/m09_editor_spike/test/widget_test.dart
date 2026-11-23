import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m09_editor_spike/main.dart';
import 'package:m09_editor_spike/proof_document.dart';
import 'package:m09_editor_spike/accessible_block.dart';
import 'package:m09_editor_spike/table_navigation.dart';

void main() {
  testWidgets('editor without an autofill group returns no autofill scope', (
    tester,
  ) async {
    await tester.pumpWidget(const ProofApp());
    await tester.pumpAndSettle();
    final editor = tester
        .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
        .editorState;
    final keyboard = editor.service.keyboardServiceKey.currentState!
        as KeyboardServiceWidgetState;
    final client = keyboard.textInputService as TextInputClient;
    expect(client.currentAutofillScope, isNull);
    expect(tester.takeException(), null);
  });
  testWidgets('table Tab traverses row-major and does not change document', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProofApp());
    await tester.pumpAndSettle();
    final editor = tester
        .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
        .editorState;
    final table = editor.document.root.children[11];
    final before = jsonEncode(editor.document.toJson());
    final first = table.children.first.children.first;
    editor.service.selectionService.updateSelection(
      Selection.collapsed(Position(path: first.path, offset: 0)),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      editor.getNodeAtPath(editor.selection!.start.path)!.delta!.toPlainText(),
      'B1',
    );
    expect(moveTableCell(editor, backward: true), KeyEventResult.handled);
    await tester.pumpAndSettle();
    expect(editor.selection!.start.path, first.path);
    expect(moveTableCell(editor, backward: true), KeyEventResult.ignored);
    expect(jsonEncode(editor.document.toJson()), before);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final destination = editor.getNodeAtPath(editor.selection!.start.path)!;
    expect(tester.testTextInput.editingState?['text'], ' B1');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: ' QB1',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    expect(destination.delta!.toPlainText(), 'QB1');
    expect(tester.takeException(), null);
  });
  testWidgets(
    'readonly rejects an in-flight IME change and keeps nested semantics',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(const ProofApp());
      await tester.pumpAndSettle();
      final editor = tester
          .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
          .editorState;
      final node = editor.document.root.children.first;
      final before = jsonEncode(editor.document.toJson());
      editor.service.selectionService.updateSelection(
        Selection.collapsed(
          Position(path: node.path, offset: node.delta!.length),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.testTextInput.hasAnyClients, true);
      await tester.tap(find.text('Readonly'));
      await tester.pumpAndSettle();
      if (tester.testTextInput.hasAnyClients) {
        final text = ' ${node.delta!.toPlainText()} DENIED';
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
        );
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(jsonEncode(editor.document.toJson()), before);
      final fields = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((w) => w.properties.readOnly == true);
      expect(fields.length, greaterThanOrEqualTo(18));
      expect(
        fields.every(
          (w) =>
              w.properties.textField == false && w.properties.onSetText == null,
        ),
        true,
      );
      expect(tester.takeException(), null);
      semantics.dispose();
    },
  );
  testWidgets('IME composing updates commit Unicode without removing math', (
    tester,
  ) async {
    await tester.pumpWidget(const ProofApp());
    await tester.pumpAndSettle();
    final editor = tester
        .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
        .editorState;
    final node = editor.document.root.children.first;
    final before = node.delta!.toPlainText();
    editor.service.selectionService.updateSelection(
      Selection.collapsed(Position(path: node.path, offset: before.length)),
    );
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, true);
    for (final suffix in [' vie', ' việ', ' Việt 📝']) {
      final value =
          ' $before$suffix'; // upstream IME anchor is one leading space
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
          composing: suffix == ' Việt 📝'
              ? TextRange.empty
              : TextRange(start: before.length + 2, end: value.length),
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(node.delta!.toPlainText(), '$before Việt 📝');
    expect(jsonEncode(node.delta!.toJson()), contains('m09_math'));
    expect(tester.takeException(), null);
  });

  testWidgets('font size affects the selected range and one undo restores it', (
    tester,
  ) async {
    await tester.pumpWidget(const ProofApp());
    await tester.pumpAndSettle();
    final editor = tester
        .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
        .editorState;
    final node = editor.document.root.children.first;
    final before = jsonEncode(node.delta!.toJson());
    await editor.formatDelta(
      Selection.single(path: node.path, startOffset: 0, endOffset: 5),
      {'font_size': 32.0},
    );
    await tester.pump();
    expect(
      node.delta!.slice(0, 5).everyAttributes((a) => a['font_size'] == 32.0),
      true,
    );
    expect(
      jsonEncode(node.delta!.slice(5).toJson()),
      jsonEncode(Delta.fromJson(jsonDecode(before)).slice(5).toJson()),
    );
    editor.undoManager.undo();
    await tester.pump();
    expect(jsonEncode(node.delta!.toJson()), before);
  });
  testWidgets(
    'accessible text action retains unaffected math/styles and has undo',
    (tester) async {
      await tester.pumpWidget(const ProofApp());
      await tester.pumpAndSettle();
      final editor = tester
          .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
          .editorState;
      final node = editor.document.root.children.first;
      final before = jsonEncode(node.delta!.toJson());
      await replaceAccessibleText(
        editor,
        node,
        '${node.delta!.toPlainText()} thêm 📝',
      );
      await tester.pump();
      expect(node.delta!.toPlainText(), endsWith(' thêm 📝'));
      expect(jsonEncode(node.delta!.toJson()), contains('m09_math'));
      expect(jsonEncode(node.delta!.toJson()), contains('font_size'));
      editor.undoManager.undo();
      await tester.pump();
      expect(jsonEncode(node.delta!.toJson()), before);
    },
  );
  test('all13 block kinds and custom attributes round trip losslessly', () {
    final doc = proofDocument();
    expect(doc.root.children.length, 13);
    final raw = jsonEncode(doc.toJson());
    expect(jsonEncode(Document.fromJson(jsonDecode(raw)).toJson()), raw);
    expect(raw, contains('m09_math'));
    expect(raw, contains('font_size'));
    expect(raw, contains('m09_id'));
    expect(
      doc.root.children[8].children.single.delta!.toPlainText(),
      'Toggle child preserved',
    );
  });

  testWidgets(
    'candidate renders nested blocks, H4, math and table without errors',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const ProofApp());
      await tester.pumpAndSettle();
      expect(find.text('Heading 4', findRichText: true), findsOneWidget);
      expect(
        find.text('Toggle child preserved', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Callout child', findRichText: true), findsOneWidget);
      expect(find.text('A1', findRichText: true), findsOneWidget);
      expect(tester.takeException(), null);
      await tester.tap(find.text('Round trip'));
      await tester.pump();
      expect(find.text('Round trip PASS'), findsOneWidget);
    },
  );

  testWidgets('collapse keeps descendants and expand restores them', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProofApp());
    await tester.pumpAndSettle();
    final editor = tester
        .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
        .editorState;
    await tester.tap(find.byTooltip('Collapse toggle'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('Toggle child preserved', findRichText: true),
      findsNothing,
    );
    expect(
      editor.document.root.children[8].children.single.delta!.toPlainText(),
      'Toggle child preserved',
    );
    await tester.tap(find.byTooltip('Expand toggle'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('Toggle child preserved', findRichText: true),
      findsOneWidget,
    );
    expect(tester.takeException(), null);
  });

  testWidgets(
    'readonly disables prototype mutation controls and input engine',
    (tester) async {
      await tester.pumpWidget(const ProofApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Readonly'));
      await tester.pump();
      expect(
        tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor)).editable,
        false,
      );
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
            .onPressed,
        null,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Size24'))
            .onPressed,
        null,
      );
      expect(find.byType(FloatingToolbar), findsNothing);
    },
  );
}
