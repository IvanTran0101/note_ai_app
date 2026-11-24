import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';

import '../notes/notes_theme_tokens.dart';
import 'accessible_builders.dart';
import 'container_block.dart';
import 'document_span.dart';
import 'divider_controls.dart';
import 'rich_editor_adapter.dart';
import 'file_block_builder.dart';

Map<String, engine.BlockComponentBuilder> documentBlockBuilders(
  BuildContext context,
  RichEditorAdapter adapter,
  FocusNode focus, {
  Widget Function(String blockId, String? attachmentId)? fileBlockBuilder,
  ValueChanged<engine.Node>? onAddBlock,
}) {
  final colors = Theme.of(context).colorScheme;
  return accessibleBuilders(
    {
      ...engine.standardBlockComponentBuilderMap,
      'm09_file': FileBlockBuilder(fileBuilder: fileBlockBuilder),
      if (kIsWeb)
        'bulleted_list': engine.BulletedListBlockComponentBuilder(
          iconBuilder: (context, node) =>
              _webBulletIcon(context, node, adapter),
        ),
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
          padding: EdgeInsetsDirectional.only(end: kIsWeb ? 22 : 14),
          child: SizedBox(
            width: 3,
            height: kIsWeb ? 24 : null,
            child: ColoredBox(color: colors.onSurface),
          ),
        ),
      ),
      'todo_list': engine.TodoListBlockComponentBuilder(
        configuration: engine.BlockComponentConfiguration(
          padding: (_) => EdgeInsets.symmetric(vertical: kIsWeb ? 3 : 4),
        ),
        textStyleBuilder: (_) => const TextStyle(),
        iconBuilder: (_, node, onCheck) => Padding(
          padding: EdgeInsetsDirectional.only(end: kIsWeb ? 6 : 0),
          child: SizedBox(
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
    adapter: adapter,
    onAddBlock: onAddBlock,
  );
}

/// Match the reference's 32px marker column, retaining nested bullet shapes.
Widget _webBulletIcon(
  BuildContext context,
  engine.Node node,
  RichEditorAdapter adapter,
) {
  var level = 0;
  for (var parent = node.parent; parent != null; parent = parent.parent) {
    if (parent.type == 'bulleted_list') level++;
  }
  final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
  return Container(
    constraints: const BoxConstraints(minWidth: 32, minHeight: 22) * scale,
    // Grow the trailing gap while keeping the marker center at its old x.
    padding: const EdgeInsetsDirectional.only(end: 10),
    child: Center(
      child: Text(
        const ['●', '◯', '□'][level % 3],
        style: adapter.editor.editorStyle.textStyleConfiguration.text,
        textScaler: TextScaler.linear(.5 * scale),
      ),
    ),
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
  final style = engine.EditorStyle.desktop(
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
  final nativeMobile =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (!nativeMobile) return style;

  // Keep the shared document styling above, while restoring AppFlowy's native
  // selection affordances that the desktop preset intentionally disables.
  return style.copyWith(
    dragHandleColor: colors.primary,
    magnifierSize: const Size(72, 48),
    mobileDragHandleBallSize: const Size(8, 8),
    mobileDragHandleWidth: 2,
    enableHapticFeedbackOnAndroid: true,
    autoDismissCollapsedHandleDuration: const Duration(seconds: 3),
  );
}
