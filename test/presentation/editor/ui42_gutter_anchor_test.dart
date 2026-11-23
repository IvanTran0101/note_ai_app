import 'package:appflowy_editor/appflowy_editor.dart' as engine;

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';
import 'package:note_ai_app/presentation/editor/rich_note_editor.dart';

void main() {
  testWidgets('gutter follows first text line for padded and nested blocks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(850, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final blocks = [
      for (var level = 1; level <= 4; level++)
        DocumentBlock(
          id: 'h$level',
          kind: DocumentBlockKind.heading,
          level: level,
          runs: [DocumentText('Heading $level')],
        ),
      DocumentBlock(
        id: 'quote',
        kind: DocumentBlockKind.quote,
        runs: const [DocumentText('Quote first line\nQuote second line')],
      ),
      DocumentBlock(
        id: 'task',
        kind: DocumentBlockKind.todo,
        checked: false,
        runs: const [DocumentText('Task first line')],
      ),
      DocumentBlock(
        id: 'callout',
        kind: DocumentBlockKind.callout,
        icon: '💡',
        runs: const [DocumentText('Callout first line')],
      ),
      DocumentBlock(
        id: 'toggle',
        kind: DocumentBlockKind.toggle,
        runs: const [DocumentText('Toggle first line')],
        children: [
          DocumentBlock(
            id: 'nested',
            kind: DocumentBlockKind.paragraph,
            runs: const [DocumentText('Nested child')],
          ),
        ],
      ),
    ];
    final adapter = RichEditorAdapter(
      document: NoteDocument(blocks),
      legacyText: '',
      canEdit: () => true,
      isLive: () => true,
      accessGeneration: () => 1,
      onChanged: () {},
    );
    final focus = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          engine.AppFlowyEditorLocalizations.delegate,
        ],
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(40),
            child: RichNoteEditor(
              adapter: adapter,
              focusNode: focus,
              header: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final scale in [1.0, 1.5]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await tester.pumpAndSettle();
      for (var i = 0; i < blocks.length; i++) {
        final node = adapter.editor.getNodeAtPath([i])!;
        adapter.editor.selection = engine.Selection.collapsed(
          engine.Position(path: [i], offset: 0),
        );
        await tester.pumpAndSettle();
        final cursor = node.selectable!.getCursorRectInPosition(
          engine.Position(path: node.path, offset: 0),
        )!;
        final center = node.selectable!.localToGlobal(cursor.center);
        final button = find.byKey(ValueKey('block-add-${blocks[i].id}'));
        expect(
          tester.getCenter(button).dy,
          closeTo(center.dy, 1),
          reason: '${blocks[i].id} at $scale: align to first text line',
        );
      }
    }
    final child = adapter.editor.getNodeAtPath([7, 0])!;
    final cursor = child.selectable!.getCursorRectInPosition(
      engine.Position(path: child.path, offset: 0),
    )!;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(
      child.selectable!.localToGlobal(cursor.center) + const Offset(40, 0),
    );
    await tester.pumpAndSettle();
    expect(adapter.gutterHover.value, 'nested');
    expect(find.byKey(const ValueKey('block-add-toggle')), findsNothing);
    expect(find.byKey(const ValueKey('block-add-nested')), findsOneWidget);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    adapter.dispose();
    focus.dispose();
  }, skip: !kIsWeb);
}
