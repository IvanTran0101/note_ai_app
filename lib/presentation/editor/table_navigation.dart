import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// Host table navigation delegates all caret/input work to the engine service.
/// TableNode stores columns; UI traversal is row-major, using explicit positions.
final tableNavigationShortcuts = <CommandShortcutEvent>[
  for (final backward in [false, true])
    CommandShortcutEvent(
      key: backward ? 'previous table cell' : 'next table cell',
      command: backward ? 'shift+tab' : 'tab',
      getDescription: () => backward ? 'Previous cell' : 'Next cell',
      handler: (editor) => moveTableCell(editor, backward: backward),
    ),
];

KeyEventResult moveTableCell(EditorState editor, {bool backward = false}) {
  final selection = editor.selection;
  if (selection == null || !selection.isSingle) return KeyEventResult.ignored;
  final paragraph = editor.getNodeAtPath(selection.start.path);
  final cell = paragraph?.parent;
  final table = cell?.parent;
  if (cell?.type != TableCellBlockKeys.type ||
      table?.type != TableBlockKeys.type) {
    return KeyEventResult.ignored;
  }
  final columns = table!.attributes[TableBlockKeys.colsLen] as int;
  final rows = table.attributes[TableBlockKeys.rowsLen] as int;
  final row = cell!.attributes[TableCellBlockKeys.rowPosition] as int;
  final column = cell.attributes[TableCellBlockKeys.colPosition] as int;
  final index = row * columns + column + (backward ? -1 : 1);
  // Leave edge focus navigation to the platform; never add rows implicitly.
  if (index < 0 || index >= rows * columns) {
    return KeyEventResult.skipRemainingHandlers;
  }
  final next = table.children.firstWhere(
    (node) =>
        node.attributes[TableCellBlockKeys.rowPosition] == index ~/ columns &&
        node.attributes[TableCellBlockKeys.colPosition] == index % columns,
  );
  editor.service.selectionService.updateSelection(
    Selection.collapsed(Position(path: next.children.first.path, offset: 0)),
  );
  return KeyEventResult.handled;
}
