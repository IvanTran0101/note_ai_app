import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';

const _defaultPadding = EdgeInsets.fromLTRB(13, 17, 19, 23);
const _customPadding = EdgeInsets.fromLTRB(2, 3, 5, 7);

void main() {
  test('per-block padding is optional and is preserved by copyWith', () {
    expect(engine.EditorStyle.desktop().blockPadding, isNull);
    expect(engine.EditorStyle.mobile().blockPadding, isNull);

    EdgeInsets perBlock(engine.Node node) =>
        node.attributes['m09_id'] == 'custom'
        ? _customPadding
        : _defaultPadding;
    final style = engine.EditorStyle.desktop(
      padding: _defaultPadding,
      blockPadding: perBlock,
    );

    expect(style.copyWith().blockPadding, same(perBlock));
    expect(
      style.copyWith(padding: EdgeInsets.zero).blockPadding,
      same(perBlock),
    );

    EdgeInsets replacement(engine.Node _) => EdgeInsets.zero;
    expect(
      style.copyWith(blockPadding: replacement).blockPadding,
      same(replacement),
    );
  });

  for (final shrinkWrap in [true, false]) {
    testWidgets(
      'page block uses per-node padding in shrinkWrap=$shrinkWrap layout',
      (tester) async {
        final style = engine.EditorStyle.desktop(
          padding: _defaultPadding,
          blockPadding: (node) => node.attributes['m09_id'] == 'custom'
              ? _customPadding
              : _defaultPadding,
        );
        final adapter = _adapter();
        await _pumpEditor(tester, adapter, style, shrinkWrap: shrinkWrap);

        _expectPadding(tester, 'custom', _customPadding);
        _expectPadding(tester, 'default', _defaultPadding);

        await tester.pumpWidget(const SizedBox.shrink());
        adapter.dispose();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('page block retains editor padding without callback '
        'in shrinkWrap=$shrinkWrap layout', (tester) async {
      final adapter = _adapter();
      await _pumpEditor(
        tester,
        adapter,
        engine.EditorStyle.desktop(padding: _defaultPadding),
        shrinkWrap: shrinkWrap,
      );

      _expectPadding(tester, 'custom', _defaultPadding);
      _expectPadding(tester, 'default', _defaultPadding);

      await tester.pumpWidget(const SizedBox.shrink());
      adapter.dispose();
      expect(tester.takeException(), isNull);
    });
  }
}

RichEditorAdapter _adapter() => RichEditorAdapter(
  document: NoteDocument([
    DocumentBlock(
      id: 'custom',
      kind: DocumentBlockKind.paragraph,
      runs: [DocumentText('Custom block')],
    ),
    DocumentBlock(
      id: 'default',
      kind: DocumentBlockKind.paragraph,
      runs: [DocumentText('Default block')],
    ),
  ]),
  legacyText: '',
  canEdit: () => true,
  isLive: () => true,
  accessGeneration: () => 1,
  onChanged: () {},
);

Future<void> _pumpEditor(
  WidgetTester tester,
  RichEditorAdapter adapter,
  engine.EditorStyle style, {
  required bool shrinkWrap,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          height: 520,
          child: engine.AppFlowyEditor(
            editorState: adapter.editor,
            editorStyle: style,
            shrinkWrap: shrinkWrap,
            editable: false,
            disableKeyboardService: true,
            disableSelectionService: true,
            disableAutoScroll: true,
            blockWrapper: (_, {required node, required child}) {
              final blockId = node.attributes['m09_id'];
              return KeyedSubtree(
                key: ValueKey('block-$blockId'),
                child: child,
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectPadding(WidgetTester tester, String blockId, EdgeInsets padding) {
  expect(
    find.ancestor(
      of: find.byKey(ValueKey('block-$blockId')),
      matching: find.byWidgetPredicate(
        (widget) => widget is Container && widget.padding == padding,
      ),
    ),
    findsOneWidget,
    reason: 'Expected page wrapper for $blockId to use $padding.',
  );
}
