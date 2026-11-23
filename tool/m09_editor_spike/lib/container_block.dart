// Renderer extension uses AppFlowy's public selectable/text/transaction services.
// It does not implement an input, caret, selection, or undo engine.
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

final class ContainerBlockBuilder extends BlockComponentBuilder {
  ContainerBlockBuilder({required this.toggle, this.editable = true});
  final bool toggle, editable;
  @override
  BlockComponentValidate get validate =>
      (node) => node.delta != null;
  @override
  BlockComponentWidget build(BlockComponentContext context) => _ContainerBlock(
    key: context.node.key,
    node: context.node,
    configuration: configuration,
    toggle: toggle,
    editable: editable,
  );
}

final class _ContainerBlock extends BlockComponentStatefulWidget {
  const _ContainerBlock({
    super.key,
    required super.node,
    required super.configuration,
    required this.toggle,
    required this.editable,
  });
  final bool toggle, editable;
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
  bool get collapsed => node.attributes['m09_collapsed'] == true;

  @override
  Widget build(BuildContext context) => widget.toggle && collapsed
      ? buildComponent(context)
      : super.build(context);

  Future<void> _toggle() async {
    final transaction = editorState.transaction
      ..updateNode(node, {'m09_collapsed': !collapsed});
    transaction.afterSelection = Selection.collapsed(
      Position(path: node.path, offset: 0),
    );
    await editorState.apply(transaction);
  }

  Widget _leading() => widget.toggle
      ? IconButton(
          tooltip: collapsed ? 'Expand toggle' : 'Collapse toggle',
          onPressed: widget.editable ? _toggle : null,
          icon: Icon(collapsed ? Icons.chevron_right : Icons.expand_more),
          visualDensity: VisualDensity.compact,
        )
      : const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.lightbulb_outline, size: 20),
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
        color: widget.toggle ? null : const Color(0xfff1f1ef),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _leading(),
            Expanded(child: text),
          ],
        ),
      ),
    );
  }
}
