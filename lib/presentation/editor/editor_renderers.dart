import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../notes/notes_theme_tokens.dart';
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
        textStyleBuilder: (_) =>
            kIsWeb ? const TextStyle(height: 1.3) : const TextStyle(),
        configuration: engine.BlockComponentConfiguration(
          padding: (node) {
            if (!kIsWeb) return const EdgeInsets.symmetric(vertical: 4);
            final level = ((node.attributes['level'] as int?) ?? 1).clamp(1, 4);
            // Calibrated against the visible Notion block/glyph geometry.
            // Engine block spacing already supplies the inter-block gap.
            return EdgeInsets.only(
              top: [27.0, 21.0, 15.0, 18.0][level - 1],
              bottom: level < 3 ? 4 : 0,
            );
          },
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
      'quote': engine.QuoteBlockComponentBuilder(
        iconBuilder: (_, _) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 14),
          child: SizedBox(width: 3, child: ColoredBox(color: colors.onSurface)),
        ),
      ),
      'todo_list': engine.TodoListBlockComponentBuilder(
        configuration: engine.BlockComponentConfiguration(
          padding: (_) => EdgeInsets.symmetric(vertical: kIsWeb ? 3 : 4),
        ),
        textStyleBuilder: (_) => const TextStyle(),
        iconBuilder: (_, node, onCheck) => SizedBox(
          width: kIsWeb ? 24 : 48,
          height: kIsWeb ? 24 : 48,
          child: Checkbox(
            value: node.attributes['checked'] == true,
            semanticLabel: 'Task complete',
            materialTapTargetSize: kIsWeb
                ? MaterialTapTargetSize.shrinkWrap
                : MaterialTapTargetSize.padded,
            visualDensity: kIsWeb
                ? VisualDensity.compact
                : VisualDensity.standard,
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
      engine.TableBlockKeys.type: engine.TableBlockComponentBuilder(
        tableStyle: engine.TableStyle(
          borderWidth: 1,
          borderColor: NoteFlowUiTokens.of(context).divider,
          borderHoverColor: colors.primary,
        ),
      ),
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
  final nativePhone = NoteFlowLayout.isNativePhone(context);
  return engine.EditorStyle.desktop(
    padding: EdgeInsets.symmetric(vertical: nativePhone ? 4 : 8),
    blockPadding: kIsWeb
        ? (node) =>
              const {
                'bulleted_list',
                'numbered_list',
                'todo_list',
              }.contains(node.type)
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(vertical: 8)
        : null,
    cursorColor: colors.onSurface,
    selectionColor: colors.primary.withValues(alpha: .22),
    textScaleFactor: MediaQuery.textScalerOf(context).scale(16) / 16,
    textStyleConfiguration: engine.TextStyleConfiguration(
      text: TextStyle(
        fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
        fontSize: nativePhone ? 17 : 16,
        height: 1.5,
        color: colors.onSurface,
      ),
      code: TextStyle(
        fontFamily: 'monospace',
        color: colors.onSurface,
        backgroundColor: colors.surfaceContainer,
      ),
    ),
    textSpanDecorator: documentSpan,
  );
}
