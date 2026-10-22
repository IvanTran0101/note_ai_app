import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/notes/note_document.dart';
import '../notes/notes_theme_tokens.dart';
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

part 'selection_toolbar_dialogs.dart';

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
      final desktop = SelectionToolbarLayout.isDesktopPopup(context);
      final hasMath = formatter.containsMath(snapshot);
      final style = _menu(
        dialogContext,
        _blockLabel(snapshot, normalText: desktop),
        snapshot,
        desktop: desktop,
      );
      final bold = _icon(
        'bold',
        Icons.format_bold,
        () => formatter.toggle(snapshot, 'bold'),
        selected: formatter.state(snapshot, 'bold').value == true,
        mixed: formatter.state(snapshot, 'bold').mixed,
        desktop: desktop,
      );
      final italic = _icon(
        'italic',
        Icons.format_italic,
        () => formatter.toggle(snapshot, 'italic'),
        selected: formatter.state(snapshot, 'italic').value == true,
        mixed: formatter.state(snapshot, 'italic').mixed,
        desktop: desktop,
      );
      final underline = _icon(
        'underline',
        Icons.format_underlined,
        () => formatter.toggle(snapshot, 'underline'),
        selected: formatter.state(snapshot, 'underline').value == true,
        mixed: formatter.state(snapshot, 'underline').mixed,
        desktop: desktop,
      );
      final strike = _icon(
        'strikethrough',
        Icons.format_strikethrough,
        () => formatter.toggle(snapshot, 'strikethrough'),
        selected: formatter.state(snapshot, 'strikethrough').value == true,
        mixed: formatter.state(snapshot, 'strikethrough').mixed,
        desktop: desktop,
      );
      final code = _icon(
        'code',
        Icons.code,
        () => formatter.toggle(snapshot, 'code'),
        selected: formatter.state(snapshot, 'code').value == true,
        mixed: formatter.state(snapshot, 'code').mixed,
        enabled: !hasMath,
        desktop: desktop,
      );
      final textColor = _icon(
        'Text color',
        Icons.format_color_text,
        () => _color(dialogContext, snapshot, false),
        desktop: desktop,
      );
      final highlight = _icon(
        'Highlight',
        Icons.highlight,
        () => _color(dialogContext, snapshot, true),
        desktop: desktop,
      );
      final link = _icon(
        'Link',
        Icons.link,
        () => _link(dialogContext, snapshot),
        enabled: !hasMath,
        desktop: desktop,
      );
      final equation = _icon(
        'Equation',
        Icons.functions,
        () {
          onPopupOpen();
          return editEquation(dialogContext, adapter, snapshot);
        },
        enabled: snapshot.selection.isSingle,
        desktop: desktop,
        glyphBuilder: (context) => Text(
          '√x',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: desktop ? 14 : 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
      final clear = _icon(
        'Clear formatting',
        Icons.format_clear,
        () => formatter.clear(snapshot),
        desktop: desktop,
      );
      final sizeButton = _sizeButton(
        dialogContext,
        snapshot,
        size,
        desktop: desktop,
      );
      return SelectionToolbarLayout(
        desktopRows: desktop
            ? [
                [style],
                [textColor, bold, italic, underline, clear, sizeButton],
                [
                  link,
                  strike,
                  code,
                  equation,
                  _more(dialogContext, snapshot, desktop: desktop),
                ],
              ]
            : null,
        children: [
          style,
          if (!desktop) textColor,
          bold,
          italic,
          underline,
          strike,
          sizeButton,
          code,
          if (desktop) textColor,
          highlight,
          link,
          equation,
          if (hasMath)
            _icon(
              'Convert equation to text',
              Icons.text_snippet_outlined,
              () => EquationCommands(adapter).convertToText(snapshot),
              enabled: snapshot.selection.isSingle,
              desktop: desktop,
            ),
          clear,
        ],
      );
    },
  );
  String _blockLabel(
    RichSelectionSnapshot snapshot, {
    bool normalText = false,
  }) {
    final labels = adapter.editor
        .getNodesInSelection(snapshot.selection.normalized)
        .where((node) => node.delta != null)
        .map(
          (node) => node.type == 'heading'
              ? normalText
                    ? 'Heading ${node.attributes['level']}'
                    : 'H${node.attributes['level']}'
              : normalText
              ? 'Normal Text'
              : 'Text',
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
    bool desktop = false,
    Widget Function(BuildContext context)? glyphBuilder,
  }) => Builder(
    builder: (context) => EditorIconButton(
      label: editorText(context, label),
      value: mixed ? editorText(context, 'Mixed') : null,
      tooltip: mixed
          ? '${editorText(context, label)} (${editorText(context, 'Mixed')})'
          : editorText(context, label),
      selected: selected,
      onPressed: enabled ? () => unawaited(action()) : null,
      compact: desktop,
      showTooltip: !desktop,
      icon: glyphBuilder?.call(context) ?? Icon(icon, size: desktop ? 18 : 20),
    ),
  );
  Widget _menu(
    BuildContext context,
    String label,
    RichSelectionSnapshot snapshot, {
    bool desktop = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final button = TextButton(
      onPressed: () => _style(context, snapshot),
      style: desktop
          ? TextButton.styleFrom(
              foregroundColor: colors.onSurface,
              backgroundColor: Colors.transparent,
              overlayColor: colors.onSurface.withValues(alpha: 0.06),
              alignment: Alignment.centerLeft,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 7),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            )
          : TextButton.styleFrom(
              foregroundColor: colors.onSurfaceVariant,
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (desktop) ...[
            const Icon(Icons.text_fields, size: 16),
            const SizedBox(width: 8),
          ],
          Text(
            editorText(context, label),
            style: desktop ? const TextStyle(fontSize: 14) : null,
          ),
          if (desktop) const Spacer(),
          Icon(desktop ? Icons.chevron_right : Icons.expand_more, size: 18),
        ],
      ),
    );
    return desktop
        ? button
        : Tooltip(message: editorText(context, 'Text style'), child: button);
  }

  Widget _sizeButton(
    BuildContext context,
    RichSelectionSnapshot snapshot,
    FormatValue size, {
    required bool desktop,
  }) {
    final colors = Theme.of(context).colorScheme;
    final defaultSize = NoteFlowLayout.isNativePhone(context) ? 17 : 16;
    final button = TextButton(
      onPressed: () => _size(context, snapshot),
      style: desktop
          ? TextButton.styleFrom(
              foregroundColor: colors.onSurface,
              backgroundColor: Colors.transparent,
              overlayColor: colors.onSurface.withValues(alpha: 0.06),
              fixedSize: const Size(36, 32),
              minimumSize: const Size(36, 32),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            )
          : TextButton.styleFrom(
              foregroundColor: colors.onSurfaceVariant,
              minimumSize: const Size(64, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
      child: Text(
        size.mixed
            ? editorText(context, 'Mixed')
            : '${size.value ?? defaultSize} pt',
        style: desktop ? const TextStyle(fontSize: 11) : null,
      ),
    );
    return desktop
        ? button
        : Tooltip(message: editorText(context, 'Font size'), child: button);
  }

  Widget _more(
    BuildContext context,
    RichSelectionSnapshot snapshot, {
    required bool desktop,
  }) {
    final hasMath = SelectionFormattingController(adapter)
        .containsMath(snapshot);
    final button = PopupMenuButton<String>(
      tooltip: desktop ? null : editorText(context, 'More'),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      iconSize: 18,
      icon: const Icon(Icons.more_horiz),
      onSelected: (value) {
        if (value == 'highlight') {
          unawaited(_color(context, snapshot, true));
        } else if (value == 'convert-equation') {
          unawaited(EquationCommands(adapter).convertToText(snapshot));
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'highlight',
          child: Text(editorText(context, 'Highlight')),
        ),
        if (hasMath)
          PopupMenuItem(
            value: 'convert-equation',
            child: Text(editorText(context, 'Convert equation to text')),
          ),
      ],
    );
    return desktop
        ? button
        : Tooltip(message: editorText(context, 'More'), child: button);
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
