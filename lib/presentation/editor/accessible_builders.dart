import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'accessible_block.dart';

/// Decorate public builders so nested paragraphs and table cells receive the
/// same host semantics as root text. Keep the original keyed selectable child.
Map<String, BlockComponentBuilder> accessibleBuilders(
  Map<String, BlockComponentBuilder> builders,
  EditorState editor,
  FocusNode focus,
  bool editable,
) => builders.map(
  (type, builder) =>
      MapEntry(type, _AccessibleBuilder(builder, editor, focus, editable)),
);

class _AccessibleBuilder extends BlockComponentBuilder {
  _AccessibleBuilder(this.delegate, this.editor, this.focus, this.editable)
    : super(configuration: delegate.configuration);
  final BlockComponentBuilder delegate;
  final EditorState editor;
  final FocusNode focus;
  final bool editable;

  @override
  BlockComponentValidate get validate => delegate.validate;
  @override
  Position start(Node node) => delegate.start(node);
  @override
  Position end(Node node) => delegate.end(node);
  @override
  BlockComponentWidget build(BlockComponentContext context) {
    final child = delegate.build(context);
    if (context.node.delta == null) return child;
    return _AccessibleComponent(
      node: context.node,
      configuration: configuration,
      editor: editor,
      focus: focus,
      editable: editable,
      child: child,
    );
  }
}

class _AccessibleComponent extends BlockComponentStatelessWidget {
  const _AccessibleComponent({
    required super.node,
    required super.configuration,
    required this.editor,
    required this.focus,
    required this.editable,
    required this.child,
  });
  final EditorState editor;
  final FocusNode focus;
  final bool editable;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = accessibleBlock(
      context,
      node: node,
      editor: editor,
      focusNode: focus,
      editable: editable,
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
