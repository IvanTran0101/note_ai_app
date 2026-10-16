// Renderer extension uses AppFlowy's public selectable/text/transaction services.
// It does not implement an input, caret, selection, or undo engine.
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'rich_editor_adapter.dart';
import 'rich_document_codec.dart';
import 'nested_block_commands.dart';
import 'document_palette.dart';
import 'callout_options.dart';
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
  @override
  BlockComponentConfiguration get configuration => widget.configuration;
  @override
  Node get node => widget.node;
  bool get collapsed =>
      !(widget.adapter.expandedToggles[RichDocumentCodec.id(node)] ?? true);
  late bool _wasCollapsed;
  @override
  void initState() {
    super.initState();
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
  Widget build(BuildContext context) => widget.toggle && collapsed
      ? buildComponent(context)
      : super.build(context);

  void _toggle() => widget.adapter.expand(RichDocumentCodec.id(node));

  Widget _leading() => widget.toggle
      ? IconButton(
          tooltip: collapsed ? 'Expand toggle' : 'Collapse toggle',
          onPressed: _toggle,
          icon: Icon(collapsed ? Icons.chevron_right : Icons.expand_more),
          visualDensity: VisualDensity.compact,
        )
      : widget.adapter.editable
      ? IconButton(
          tooltip: 'Callout style',
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _leading(),
            Expanded(child: text),
            if (widget.adapter.editable)
              IconButton(
                tooltip: 'Add nested block',
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
