import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/notes/note_document.dart';
import 'basic_block_commands.dart';
import 'document_palette.dart';
import 'editor_value_dialog.dart';
import 'editor_copy.dart';
import 'editor_icon_button.dart';
import 'editor_popup_guard.dart';
import 'equation_commands.dart';
import 'rich_editor_adapter.dart';
import 'selection_formatting_controller.dart';
import 'selection_toolbar_layout.dart';

final class SelectionToolbar extends StatelessWidget {
  const SelectionToolbar({
    super.key,
    required this.adapter,
    required this.dialogContext,
    required this.onPopupOpen,
  });
  final RichEditorAdapter adapter;
  final BuildContext dialogContext;
  final VoidCallback onPopupOpen;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: adapter,
    builder: (context, _) {
      final snapshot = adapter.capture();
      if (snapshot == null) return const SizedBox.shrink();
      final formatter = SelectionFormattingController(adapter);
      final size = formatter.state(snapshot, 'font_size');
      return SelectionToolbarLayout(
        children: [
          _menu(
            dialogContext,
            _blockLabel(snapshot),
            Icons.text_fields,
            snapshot,
          ),
          for (final entry in const {
            'bold': Icons.format_bold,
            'italic': Icons.format_italic,
            'underline': Icons.format_underlined,
            'strikethrough': Icons.format_strikethrough,
            'code': Icons.code,
          }.entries)
            _icon(
              entry.key,
              entry.value,
              () => formatter.toggle(snapshot, entry.key),
              selected: formatter.state(snapshot, entry.key).value == true,
              mixed: formatter.state(snapshot, entry.key).mixed,
              enabled: entry.key != 'code' || !formatter.containsMath(snapshot),
            ),
          _icon(
            'Text color',
            Icons.format_color_text,
            () => _color(dialogContext, snapshot, false),
          ),
          _icon(
            'Highlight',
            Icons.highlight,
            () => _color(dialogContext, snapshot, true),
          ),
          TextButton(
            onPressed: () => _size(dialogContext, snapshot),
            child: Text(
              size.mixed
                  ? editorText(context, 'Mixed')
                  : '${size.value ?? 16} pt',
            ),
          ),
          _icon(
            'Link',
            Icons.link,
            () => _link(dialogContext, snapshot),
            enabled: !formatter.containsMath(snapshot),
          ),
          _icon('Equation', Icons.functions, () {
            onPopupOpen();
            return editEquation(dialogContext, adapter, snapshot);
          }, enabled: snapshot.selection.isSingle),
          if (formatter.containsMath(snapshot))
            _icon(
              'Convert equation to text',
              Icons.text_snippet_outlined,
              () => EquationCommands(adapter).convertToText(snapshot),
              enabled: snapshot.selection.isSingle,
            ),
          _icon(
            'Clear formatting',
            Icons.format_clear,
            () => formatter.clear(snapshot),
          ),
        ],
      );
    },
  );
  String _blockLabel(RichSelectionSnapshot snapshot) {
    final labels = adapter.editor
        .getNodesInSelection(snapshot.selection.normalized)
        .where((node) => node.delta != null)
        .map(
          (node) =>
              node.type == 'heading' ? 'H${node.attributes['level']}' : 'Text',
        )
        .toSet();
    return labels.length == 1 ? labels.single : 'Mixed';
  }

  Widget _icon(
    String label,
    IconData icon,
    Future<Object?> Function() action, {
    bool? selected,
    bool mixed = false,
    bool enabled = true,
  }) => Builder(
    builder: (context) => EditorIconButton(
      label: editorText(context, label),
      value: mixed ? editorText(context, 'Mixed') : null,
      tooltip: mixed
          ? '${editorText(context, label)} (${editorText(context, 'Mixed')})'
          : editorText(context, label),
      selected: selected,
      onPressed: enabled ? () => unawaited(action()) : null,
      icon: Icon(icon, size: 20),
    ),
  );
  Widget _menu(
    BuildContext context,
    String label,
    IconData icon,
    RichSelectionSnapshot snapshot,
  ) => Tooltip(
    message: editorText(context, 'Text style'),
    child: TextButton(
      onPressed: () => _style(context, snapshot),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(editorText(context, label)),
          const Icon(Icons.expand_more, size: 18),
        ],
      ),
    ),
  );
  Future<void> _style(
    BuildContext context,
    RichSelectionSnapshot snapshot,
  ) async {
    onPopupOpen();
    final choice = await guardedEditorDialog<BasicBlockChoice>(
      context,
      adapter,
      snapshot,
      (context) => SimpleDialog(
        title: Text(editorText(context, 'Text style')),
        children: [
          for (final choice in basicBlockChoices.take(5))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, choice),
              child: Text(editorText(context, choice.label)),
            ),
        ],
      ),
    );
    if (choice != null) {
      await BasicBlockCommands(adapter)
          .choose(choice, snapshot, popupOwnsFocus: true);
    }
  }

  Future<void> _size(
    BuildContext context,
    RichSelectionSnapshot snapshot,
  ) async {
    onPopupOpen();
    final formatter = SelectionFormattingController(adapter);
    final chosen = await guardedEditorDialog<String>(
      context,
      adapter,
      snapshot,
      (context) => SimpleDialog(
        title: Text(editorText(context, 'Font size')),
        children: [
          for (final size in [12, 14, 16, 18, 24, 32])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, '$size'),
              child: Text('$size pt'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'custom'),
            child: Text(editorText(context, 'Custom size (12–48)')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'reset'),
            child: Text(editorText(context, 'Reset size')),
          ),
        ],
      ),
    );
    if (chosen == null || !context.mounted) return;
    if (chosen == 'custom') {
      final value = await editorValueDialog(
        context,
        title: 'Font size',
        label: 'Size (12–48)',
        initial: '${formatter.state(snapshot, 'font_size').value ?? 16}',
        validate: validateEditorSize,
        adapter: adapter,
        snapshot: snapshot,
      );
      if (value != null) {
        await formatter.size(
          snapshot,
          double.parse(value),
          popupOwnsFocus: true,
        );
      }
    } else {
      await formatter.size(
        snapshot,
        chosen == 'reset' ? null : double.parse(chosen),
        popupOwnsFocus: true,
      );
    }
  }

  Future<void> _link(
    BuildContext context,
    RichSelectionSnapshot snapshot,
  ) async {
    onPopupOpen();
    final formatter = SelectionFormattingController(adapter);
    final value = await editorValueDialog(
      context,
      title: 'Link',
      label: 'https://… (empty to remove)',
      initial: formatter.state(snapshot, 'href').value as String? ?? '',
      validate: validateEditorLink,
      adapter: adapter,
      snapshot: snapshot,
    );
    if (value != null) {
      await formatter.link(
        snapshot,
        value.isEmpty ? null : value,
        popupOwnsFocus: true,
      );
    }
  }

  Future<void> _color(
    BuildContext context,
    RichSelectionSnapshot snapshot,
    bool highlight,
  ) async {
    onPopupOpen();
    final selected = await guardedEditorDialog<String>(
      context,
      adapter,
      snapshot,
      (context) => SimpleDialog(
        title: Text(
          editorText(context, highlight ? 'Highlight' : 'Text color'),
        ),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'reset'),
            child: Text(editorText(context, 'Default')),
          ),
          for (final color in DocumentColor.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, color.name),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    color: DocumentPalette.text(
                      color,
                      Theme.of(context).brightness,
                    ),
                    size: 16,
                  ),
                  const SizedBox(width: 12),
                  Text(editorText(context, color.name)),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected != null) {
      await SelectionFormattingController(adapter).color(
        snapshot,
        selected == 'reset' ? null : DocumentColor.values.byName(selected),
        highlight: highlight,
        popupOwnsFocus: true,
      );
    }
  }
}

Future<void> editEquation(
  BuildContext context,
  RichEditorAdapter adapter,
  RichSelectionSnapshot snapshot,
) async {
  final commands = EquationCommands(adapter);
  final initial = commands.initialExpression(snapshot);
  if (initial == null) return;
  final value = await editorValueDialog(
    context,
    title: 'Inline equation',
    label: r'LaTeX, e.g. \sqrt{x}',
    initial: initial,
    validate: validateEditorEquation,
    adapter: adapter,
    snapshot: snapshot,
    equation: true,
  );
  if (value != null) {
    await commands.replace(snapshot, value, popupOwnsFocus: true);
  }
}
