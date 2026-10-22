import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'editor_popup_guard.dart';
import 'editor_copy.dart';
import 'editor_icon_button.dart';
import 'rich_editor_adapter.dart';
import 'slash_command_controller.dart';
import 'table_commands.dart';

/// Touch controls keep a guarded caret snapshot while their popup owns focus.
/// The editor/document writer and history remain the single engine owner.
final class EditorControls extends StatefulWidget {
  const EditorControls({
    super.key,
    required this.adapter,
    required this.slash,
    this.onBlocks,
    this.blocksOpen = false,
  });
  final RichEditorAdapter adapter;
  final SlashCommandController slash;
  final VoidCallback? onBlocks;
  final bool blocksOpen;
  @override
  State<EditorControls> createState() => _EditorControlsState();
}

final class _EditorControlsState extends State<EditorControls> {
  RichSelectionSnapshot? _last, _pointer;
  RichEditorAdapter get adapter => widget.adapter;
  RichSelectionSnapshot? _selection() {
    final current = adapter.capture(range: false);
    if (current != null) _last = current;
    return current ??
        (_last != null && adapter.accepts(_last!, popupOwnsFocus: true)
            ? _last
            : null);
  }

  RichSelectionSnapshot? _takeSelection() {
    final captured = _pointer;
    _pointer = null;
    return captured != null && adapter.accepts(captured, popupOwnsFocus: true)
        ? captured
        : _selection();
  }

  Widget _button(String label, IconData icon, VoidCallback action) => Listener(
    onPointerDown: (_) => _pointer = _selection(),
    child: EditorIconButton(
      label: editorText(context, label),
      icon: Icon(icon, size: 20),
      onPressed: action,
      compact: kIsWeb && MediaQuery.sizeOf(context).width >= 720,
    ),
  );

  void _blocks() {
    final snapshot = _takeSelection();
    if (snapshot != null) {
      adapter.editor.selection = snapshot.selection;
    } else {
      final node = adapter.editor.document.root.children.first;
      adapter.editor.selection = engine.Selection.collapsed(
        engine.Position(path: node.path, offset: 0),
      );
    }
    widget.slash.openTouch();
  }

  Future<void> _table() async {
    final snapshot = _takeSelection();
    if (snapshot == null) return;
    final chosen = await guardedEditorDialog<TableChange>(
      context,
      adapter,
      snapshot,
      (context) => SimpleDialog(
        title: Text(editorText(context, 'Table options')),
        children: [
          for (final entry in const {
            TableChange.addRow: 'Add row below',
            TableChange.removeRow: 'Delete row',
            TableChange.addColumn: 'Add column after',
            TableChange.removeColumn: 'Delete column',
            TableChange.headerRow: 'Toggle header row',
            TableChange.headerColumn: 'Toggle header column',
            TableChange.paragraphAfter: 'Add text after table',
          }.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, entry.key),
              child: Text(editorText(context, entry.value)),
            ),
        ],
      ),
    );
    if (chosen != null) {
      await TableCommands(adapter)
          .change(chosen, snapshot, popupOwnsFocus: true);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: adapter,
    builder: (_, _) {
      final selection = _selection();
      final table = selection == null
          ? null
          : TableCommands(adapter).tableAt(selection);
      return Row(
        children: [
          _button(
            widget.blocksOpen ? 'Close block menu' : 'Add block',
            Icons.add,
            widget.onBlocks ?? _blocks,
          ),
          if (!kIsWeb)
            EditorIconButton(
              label: editorText(context, 'Redo'),
              icon: const Icon(Icons.redo, size: 22),
              onPressed: adapter.editor.undoManager.redoStack.isEmpty
                  ? null
                  : adapter.editor.undoManager.redo,
            ),
          if (!kIsWeb)
            EditorIconButton(
              label: editorText(context, 'Undo'),
              icon: const Icon(Icons.undo, size: 22),
              onPressed: adapter.editor.undoManager.undoStack.isEmpty
                  ? null
                  : adapter.editor.undoManager.undo,
            ),
          const Spacer(),
          if (table != null)
            _button(
              'Table options',
              Icons.table_chart_outlined,
              () => unawaited(_table()),
            ),
        ],
      );
    },
  );
}
