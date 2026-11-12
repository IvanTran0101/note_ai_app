import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'accessible_block.dart';
import 'block_insert_gutter.dart';
import 'rich_editor_adapter.dart';

import 'package:flutter/foundation.dart' show kIsWeb, ValueListenable;

/// Decorate public builders so nested paragraphs and table cells receive the
/// same host semantics as root text. Keep the original keyed selectable child.
Map<String, BlockComponentBuilder> accessibleBuilders(
  Map<String, BlockComponentBuilder> builders,
  EditorState editor,
  FocusNode focus,
  bool editable, {
  RichEditorAdapter? adapter,
  ValueChanged<Node>? onAddBlock,
}) => builders.map(
  (type, builder) => MapEntry(
    type,
    _AccessibleBuilder(builder, editor, focus, editable, adapter, onAddBlock),
  ),
);

class _AccessibleBuilder extends BlockComponentBuilder {
  _AccessibleBuilder(
    this.delegate,
    this.editor,
    this.focus,
    this.editable,
    this.adapter,
    this.onAddBlock,
  ) : super(configuration: delegate.configuration);
  final BlockComponentBuilder delegate;
  final EditorState editor;
  final FocusNode focus;
  final bool editable;
  final RichEditorAdapter? adapter;
  final ValueChanged<Node>? onAddBlock;

  @override
  BlockComponentValidate get validate => delegate.validate;
  @override
  Position start(Node node) => delegate.start(node);
  @override
  Position end(Node node) => delegate.end(node);
  @override
  BlockComponentWidget build(BlockComponentContext context) {
    final child = delegate.build(context);
    final content = context.node.delta == null
        ? child
        : _AccessibleComponent(
            node: context.node,
            configuration: configuration,
            editor: editor,
            focus: focus,
            editable: editable,
            inputSuspended: adapter?.menuOwnsInput,
            child: child,
          );
    if (!kIsWeb ||
        !editable ||
        context.node.type == 'page' ||
        context.node.path.isEmpty ||
        adapter == null ||
        onAddBlock == null ||
        context.node.parent?.type == TableCellBlockKeys.type ||
        context.node.type == TableCellBlockKeys.type) {
      return content;
    }
    return _GutterComponent(
      node: context.node,
      configuration: configuration,
      adapter: adapter!,
      onAdd: () => onAddBlock!(context.node),
      child: content,
    );
  }
}

final class _GutterComponent extends BlockComponentStatelessWidget {
  const _GutterComponent({
    required super.node,
    required super.configuration,
    required this.adapter,
    required this.onAdd,
    required this.child,
  });
  final RichEditorAdapter adapter;
  final VoidCallback onAdd;
  final Widget child;
  @override
  Widget build(BuildContext context) => BlockInsertGutter(
    node: node,
    adapter: adapter,
    onAdd: onAdd,
    child: child,
  );
}

class _AccessibleComponent extends BlockComponentStatelessWidget {
  const _AccessibleComponent({
    required super.node,
    required super.configuration,
    required this.editor,
    required this.focus,
    required this.editable,
    this.inputSuspended,
    required this.child,
  });
  final EditorState editor;
  final FocusNode focus;
  final bool editable;
  final ValueListenable<bool>? inputSuspended;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = accessibleBlock(
      context,
      node: node,
      editor: editor,
      focusNode: focus,
      editable: editable,
      inputSuspended: inputSuspended,
      child: child,
    );
    // Paragraph/list/container builders already render their children. The
    // public Heading/Quote builders do not; keep preserved children visible
    // and selectable after a container conversion using the same renderer.
    if (!const ['heading', 'quote'].contains(node.type) ||
        node.children.isEmpty) {
      return text;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        text,
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 24),
          child: Column(
            children: [
              for (final nested in node.children)
                editor.renderer.build(context, nested),
            ],
          ),
        ),
      ],
    );
  }
}
