import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/editor/editor_controls.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';
import 'package:note_ai_app/presentation/editor/rich_note_editor.dart';

void main() {
  testWidgets('metadata stays after body and updates without replacing input', (
    tester,
  ) async {
    final adapter = _adapter(), focus = FocusNode();
    final field = TextEditingController();
    Widget host(String label) => _host(
      adapter,
      focus,
      footer: Column(
        children: [
          Text(label),
          TextField(key: const ValueKey('metadata-field'), controller: field),
        ],
      ),
    );
    await tester.pumpWidget(host('Metadata'));
    await tester.pumpAndSettle();
    final body = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText() == 'body',
    );
    expect(
      tester.getTopLeft(find.text('Metadata')).dy,
      greaterThan(tester.getBottomLeft(body).dy),
    );
    final keyboard = adapter.editor.service.keyboardService;
    await tester.pumpWidget(host('Updated metadata'));
    await tester.pumpAndSettle();
    expect(adapter.editor.service.keyboardService, same(keyboard));
    await tester.tap(find.byKey(const ValueKey('metadata-field')));
    await tester.enterText(
      find.byKey(const ValueKey('metadata-field')),
      'value',
    );
    await tester.pump();
    expect(adapter.plainText, 'body');
    expect(adapter.revision, 0);
    expect(field.text, 'value');
    await tester.pumpWidget(const SizedBox());
    adapter.dispose();
    focus.dispose();
    field.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard menu selection scrolls the last block into view', (
    tester,
  ) async {
    // The Add block action lives in the native rail that surfaces above the
    // IME once the editable editor owns focus.
    tester.view
      ..physicalSize = const Size(411, 914)
      ..devicePixelRatio = 1
      ..viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.reset);
    final adapter = _adapter(), focus = FocusNode();
    await tester.pumpWidget(_host(adapter, focus));
    await tester.pumpAndSettle();
    focus.requestFocus();
    await tester.pumpAndSettle();
    final selection = engine.Selection.collapsed(
      engine.Position(path: [0], offset: 4),
    );
    adapter.editor.selection = selection;
    await tester.pumpAndSettle();
    expect(find.byTooltip('Add block'), findsOneWidget);
    await tester.tap(find.byTooltip('Add block'));
    await tester.pumpAndSettle();
    // The rail may still be settling out while the sheet owns focus, so read
    // the menu controller from whichever mounted controls use it.
    final controls = tester
        .widgetList<EditorControls>(find.byType(EditorControls))
        .last;
    expect(controls.slash.visible, isTrue);
    expect(controls.slash.snapshot?.selection, selection);
    controls.slash.move(12);
    await tester.pumpAndSettle();
    expect(find.text('Divider').hitTestable(), findsOneWidget);
    controls.slash.move(1);
    await tester.pumpAndSettle();
    expect(find.text('File').hitTestable(), findsOneWidget);
    controls.slash.move(1);
    await tester.pumpAndSettle();
    expect(find.text('Text').hitTestable(), findsOneWidget);
    // Moving the menu highlight does not rewrite the captured caret.
    expect(controls.slash.snapshot?.selection, selection);
    await tester.pumpWidget(const SizedBox());
    focus.unfocus();
    adapter.dispose();
    focus.dispose();
    expect(tester.takeException(), isNull);
  });
}

RichEditorAdapter _adapter() => RichEditorAdapter(
  document: null,
  legacyText: 'body',
  canEdit: () => true,
  isLive: () => true,
  accessGeneration: () => 1,
  onChanged: () {},
);

Widget _host(
  RichEditorAdapter adapter,
  FocusNode focus, {
  Widget footer = const SizedBox.shrink(),
}) => MaterialApp(
  localizationsDelegates: const [engine.AppFlowyEditorLocalizations.delegate],
  home: Scaffold(
    body: RichNoteEditor(
      adapter: adapter,
      focusNode: focus,
      header: const SizedBox(height: 80, child: Text('Title')),
      footer: footer,
    ),
  ),
);
