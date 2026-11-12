// Renderer extension uses AppFlowy's public selectable/text/transaction services.
// It does not implement an input, caret, selection, or undo engine.
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
import 'package:flutter/material.dart';

import 'rich_editor_adapter.dart';
import 'rich_document_codec.dart';
import 'nested_block_commands.dart';
import 'document_palette.dart';
import 'callout_options.dart';
import 'editor_icon_button.dart';
import 'editor_copy.dart';
import 'rich_inline_codec.dart';
import '../../domain/notes/note_document.dart' show DocumentColor;

final class ContainerBlockBuilder extends BlockComponentBuilder {
  ContainerBlockBuilder({required this.toggle, required this.adapter});
  final bool toggle;
  final RichEditorAdapter adapter;
  @override
  BlockComponentValidate get validate =>
      (node) => node.delta != null;
  @override
  BlockComponentWidget build(BlockComponentContext context) => _ContainerBlock(
    key: context.node.key,
    node: context.node,
    configuration: configuration,
    toggle: toggle,
    adapter: adapter,
  );
}

final class _ContainerBlock extends BlockComponentStatefulWidget {
  const _ContainerBlock({
    super.key,
    required super.node,
    required super.configuration,
    required this.toggle,
    required this.adapter,
  });
  final bool toggle;
  final RichEditorAdapter adapter;
  @override
  State<_ContainerBlock> createState() => _ContainerBlockState();
}

final class _ContainerBlockState extends State<_ContainerBlock>
    with
        SelectableMixin,
        DefaultSelectableMixin,
        BlockComponentConfigurable,
        BlockComponentBackgroundColorMixin,
        BlockComponentTextDirectionMixin,
        BlockComponentAlignMixin,
        NestedBlockComponentStatefulWidgetMixin<_ContainerBlock> {
  @override
  final forwardKey = GlobalKey(debugLabel: 'm09_container_text');
  @override
  GlobalKey<State<StatefulWidget>> get containerKey => widget.node.key;
  @override
  final blockComponentKey = GlobalKey(debugLabel: 'm09_container_block');
  double? _measuredToggleCursorCenterY;
  bool _toggleCursorMeasurementScheduled = false;
  @override
  BlockComponentConfiguration get configuration => widget.configuration;
  @override
  Node get node => widget.node;
  @override
  EdgeInsets get indentPadding {
    final base = super.indentPadding;
    if (!widget.toggle || !kIsWeb) return base;
    final extra = base.left > base.right
        ? const EdgeInsets.only(left: 8)
        : const EdgeInsets.only(right: 8);
    return EdgeInsets.fromLTRB(
      base.left + extra.left,
      base.top + extra.top,
      base.right + extra.right,
      base.bottom + extra.bottom,
    );
  }

  bool get collapsed =>
      !(widget.adapter.expandedToggles[RichDocumentCodec.id(node)] ??
          node.children.isNotEmpty);
  late bool _wasCollapsed;
  @override
  void initState() {
    super.initState();
    if (widget.toggle) {
      // New empty toggles start collapsed like Notion. Existing toggles with
      // content stay visible when an editor is reopened.
      widget.adapter.expandedToggles.putIfAbsent(
        RichDocumentCodec.id(node),
        () => node.children.isNotEmpty,
      );
    }
    _wasCollapsed = collapsed;
    widget.adapter.addListener(_expansionChanged);
  }

  void _expansionChanged() {
    if (mounted && _wasCollapsed != collapsed) {
      setState(() => _wasCollapsed = collapsed);
    }
  }

  @override
  void dispose() {
    widget.adapter.removeListener(_expansionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final component = widget.toggle && collapsed
        ? buildComponent(context)
        : super.build(context);
    if (!widget.toggle ||
        collapsed ||
        node.children.isNotEmpty ||
        !widget.adapter.editable) {
      return component;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        component,
        Padding(
          padding: EdgeInsetsDirectional.only(start: kIsWeb ? 32 : 24, top: 2),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey('m09-toggle-empty-${RichDocumentCodec.id(node)}'),
              onTap: () => NestedBlockCommands(widget.adapter).addChild(node),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  editorText(context, 'Empty toggle. Click to add a block.'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _toggle() {
    final selection = editorState.selection;
    bool insideChild(Position position) =>
        position.path.length > node.path.length &&
        listEquals(position.path.take(node.path.length).toList(), node.path);
    if (!collapsed &&
        selection != null &&
        (insideChild(selection.start) || insideChild(selection.end))) {
      // Keep the caret visible when its child disappears behind the disclosure.
      editorState.selection = Selection.collapsed(
        Position(path: node.path, offset: node.delta?.length ?? 0),
      );
    }
    widget.adapter.expand(RichDocumentCodec.id(node));
  }

  Widget _leading() => widget.adapter.editable
      ? EditorIconButton(
          label: editorText(context, 'Callout style'),
          onPressed: () => showCalloutOptions(context, node, widget.adapter),
          icon: Text(
            node.attributes['m09_icon'] as String? ?? '💡',
            style: const TextStyle(fontSize: 20),
          ),
        )
      : Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
            node.attributes['m09_icon'] as String? ?? '💡',
            style: const TextStyle(fontSize: 20),
          ),
        );

  Widget _toggleRow(Widget text) {
    final label = editorText(
      context,
      collapsed ? 'Expand toggle' : 'Collapse toggle',
    );
    final hitTarget = kIsWeb ? 24.0 : 48.0;
    final firstLineHeight = _toggleFirstLineHeight;
    const targetWidth = 24.0;
    const iconSize = 16.0;
    final iconCenterY = _measuredToggleCursorCenterY ?? firstLineHeight / 2;
    final iconTop = (iconCenterY - iconSize / 2)
        .clamp(0.0, double.infinity)
        .toDouble();
    final targetHeight = [
      hitTarget,
      firstLineHeight,
      iconCenterY + iconSize / 2,
    ].reduce((a, b) => a > b ? a : b);
    _scheduleToggleCursorMeasurement();
    final icon = AnimatedRotation(
      turns: collapsed ? 0 : .25,
      duration: const Duration(milliseconds: 120),
      child: Icon(
        Icons.play_arrow,
        size: iconSize,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );

    return Row(
      key: ValueKey('m09-toggle-row-${RichDocumentCodec.id(node)}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MergeSemantics(
          child: Semantics(
            key: ValueKey(
              'm09-toggle-disclosure-${RichDocumentCodec.id(node)}',
            ),
            label: label,
            button: true,
            expanded: !collapsed,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _toggle,
                child: SizedBox(
                  width: targetWidth,
                  height: targetHeight,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: EdgeInsets.only(top: iconTop),
                      child: icon,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (kIsWeb) const SizedBox(width: 8),
        Expanded(child: text),
      ],
    );
  }

  void _scheduleToggleCursorMeasurement() {
    if (_toggleCursorMeasurementScheduled) return;
    _toggleCursorMeasurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _toggleCursorMeasurementScheduled = false;
      if (!mounted || !widget.toggle) return;
      final selectable = node.selectable;
      final cursor = selectable?.getCursorRectInPosition(
        Position(path: node.path, offset: 0),
      );
      final blockContext = blockComponentKey.currentContext;
      final blockObject = blockContext?.findRenderObject();
      if (cursor == null || blockObject is! RenderBox) return;
      final cursorCenterGlobal = selectable!.localToGlobal(cursor.center);
      final rowTopGlobal = blockObject.localToGlobal(Offset(0, padding.top));
      final centerY = cursorCenterGlobal.dy - rowTopGlobal.dy;
      if (!centerY.isFinite ||
          (_measuredToggleCursorCenterY != null &&
              (centerY - _measuredToggleCursorCenterY!).abs() < .25)) {
        return;
      }
      setState(() => _measuredToggleCursorCenterY = centerY);
    });
  }

  double get _toggleFirstLineHeight {
    final configuration = editorState.editorStyle.textStyleConfiguration;
    var fontSize = configuration.text.fontSize ?? 16;
    final inserts = node.delta?.whereType<TextInsert>() ?? const [];
    for (final insert in inserts) {
      if (insert.text.isEmpty) continue;
      final explicitSize = insert.attributes?['font_size'];
      if (explicitSize is num) fontSize = explicitSize.toDouble();
      break;
    }
    return fontSize *
        configuration.lineHeight *
        editorState.editorStyle.textScaleFactor;
  }

  @override
  Widget buildComponent(
    BuildContext context, {
    bool withBackgroundColor = true,
  }) {
    final text = AppFlowyRichText(
      key: forwardKey,
      delegate: this,
      node: node,
      editorState: editorState,
      textSpanDecorator: (span) =>
          span.updateTextStyle(textStyleWithTextSpan(textSpan: span)),
      cursorColor: editorState.editorStyle.cursorColor,
      selectionColor: editorState.editorStyle.selectionColor,
      textDirection: calculateTextDirection(
        layoutDirection: Directionality.of(context),
      ),
    );
    return BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [BlockSelectionType.block],
      child: Container(
        key: blockComponentKey,
        padding: padding,
        color: widget.toggle
            ? null
            : DocumentPalette.highlight(
                RichInlineCodec.color(node.attributes['m09_tone']) ??
                    DocumentColor.gray,
                Theme.of(context).brightness,
              ),
        child: widget.toggle
            ? _toggleRow(text)
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _leading(),
                  Expanded(child: text),
                  if (widget.adapter.editable)
                    EditorIconButton(
                      label: editorText(context, 'Add nested block'),
                      onPressed: () =>
                          NestedBlockCommands(widget.adapter).addChild(node),
                      icon: const Icon(Icons.add, size: 18),
                    ),
                ],
              ),
      ),
    );
  }
}
