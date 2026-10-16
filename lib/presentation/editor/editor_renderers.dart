import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';

import 'accessible_builders.dart';
import 'container_block.dart';
import 'document_span.dart';
import 'divider_controls.dart';
import 'rich_editor_adapter.dart';

Map<String, engine.BlockComponentBuilder> documentBlockBuilders(
  BuildContext context,
  RichEditorAdapter adapter,
  FocusNode focus,
) {
  final colors = Theme.of(context).colorScheme;
  return accessibleBuilders(
    {
      ...engine.standardBlockComponentBuilderMap,
      // The upstream heading decorator recursively reapplies block defaults after
      // inline decoration. Span-level defaults preserve explicit range size/marks.
      'heading': engine.HeadingBlockComponentBuilder(
        textStyleBuilder: (_) => const TextStyle(),
        configuration: engine.BlockComponentConfiguration(
          placeholderText: (node) => 'Heading ${node.attributes['level']}',
          placeholderTextStyle: (node, {textSpan}) => TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: [
              30.0,
              24.0,
              20.0,
              18.0,
            ][((node.attributes['level'] as int?) ?? 1).clamp(1, 4) - 1],
          ),
        ),
      ),
      'quote': engine.QuoteBlockComponentBuilder(),
      'todo_list': engine.TodoListBlockComponentBuilder(
        textStyleBuilder: (_) => const TextStyle(),
        iconBuilder: (_, node, onCheck) => SizedBox(
          width: 48,
          height: 48,
          child: Checkbox(
            value: node.attributes['checked'] == true,
            semanticLabel: 'Task complete',
            onChanged: adapter.editable ? (_) => onCheck() : null,
          ),
        ),
      ),
      'divider': engine.DividerBlockComponentBuilder(
        lineColor: colors.outlineVariant,
        wrapper: (context, node, child) =>
            dividerControls(context, node, child, adapter),
      ),
      'm09_toggle': ContainerBlockBuilder(toggle: true, adapter: adapter),
      'm09_callout': ContainerBlockBuilder(toggle: false, adapter: adapter),
      engine.TableCellBlockKeys.type: engine.TableCellBlockComponentBuilder(
        colorBuilder: (_, cell) => _headerColor(colors, cell),
      ),
    },
    adapter.editor,
    focus,
    adapter.editable,
  );
}

Color? _headerColor(ColorScheme colors, engine.Node cell) {
  final table = cell.parent;
  return table?.attributes['m09_header_row'] == true &&
              cell.attributes['rowPosition'] == 0 ||
          table?.attributes['m09_header_column'] == true &&
              cell.attributes['colPosition'] == 0
      ? colors.surfaceContainer
      : null;
}

engine.EditorStyle documentEditorStyle(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return engine.EditorStyle.desktop(
    padding: const EdgeInsets.symmetric(vertical: 8),
    cursorColor: colors.onSurface,
    selectionColor: colors.primary.withValues(alpha: .22),
    textScaleFactor: MediaQuery.textScalerOf(context).scale(16) / 16,
    textStyleConfiguration: engine.TextStyleConfiguration(
      text: TextStyle(fontSize: 16, height: 1.5, color: colors.onSurface),
      code: TextStyle(
        fontFamily: 'monospace',
        color: colors.onSurface,
        backgroundColor: colors.surfaceContainer,
      ),
    ),
    textSpanDecorator: documentSpan,
  );
}
