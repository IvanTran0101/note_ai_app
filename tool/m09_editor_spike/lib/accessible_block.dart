import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// Host accessibility actions delegate to the same editor transaction engine.
Widget accessibleBlock(
  BuildContext context, {
  required Node node,
  required Widget child,
  required EditorState editor,
  required bool editable,
  required FocusNode focusNode,
}) {
  final delta = node.delta;
  if (delta == null) return child;
  return _AccessibleBlock(
    node: node,
    editor: editor,
    editable: editable,
    focusNode: focusNode,
    child: child,
  );
}

class _AccessibleBlock extends StatefulWidget {
  const _AccessibleBlock({
    required this.node,
    required this.editor,
    required this.editable,
    required this.focusNode,
    required this.child,
  });
  final Node node;
  final EditorState editor;
  final bool editable;
  final FocusNode focusNode;
  final Widget child;
  @override
  State<_AccessibleBlock> createState() => _AccessibleBlockState();
}

class _AccessibleBlockState extends State<_AccessibleBlock> {
  bool semanticFocus = false;
  bool activating = false;

  @override
  void initState() {
    super.initState();
    widget.editor.selectionNotifier.addListener(selectionChanged);
  }

  @override
  void dispose() {
    widget.editor.selectionNotifier.removeListener(selectionChanged);
    super.dispose();
  }

  void selectionChanged() {
    if (!mounted || semanticFocus || activating || !widget.editable) return;
    if (widget.editor.selection?.start.path.equals(widget.node.path) == true) {
      unawaited(focusFromSemantics());
    }
  }

  Future<void> focusFromSemantics() async {
    if (!widget.editable || activating) return;
    activating = true;
    setState(() => semanticFocus = false);
    widget.focusNode.requestFocus();
    final selection = widget.editor.selection;
    if (selection?.start.path.equals(widget.node.path) != true) {
      widget.editor.service.selectionService.updateSelection(
        Selection.collapsed(
          Position(path: widget.node.path, offset: widget.node.delta!.length),
        ),
      );
    }
    // Let framework/view focus settle before the semantic editing element
    // acquires DOM focus; otherwise the canvas focus change blurs it again.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && widget.editable && widget.focusNode.hasFocus) {
      setState(() => semanticFocus = true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => activating = false);
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final editor = widget.editor;
    final focusNode = widget.focusNode;
    final editable = widget.editable;
    return ListenableBuilder(
      listenable: Listenable.merge([node, editor.selectionNotifier, focusNode]),
      builder: (context, _) {
        final selected = editor.selection;
        final plain = node.delta!.toPlainText();
        return Semantics(
          container: true,
          explicitChildNodes: true,
          textField: editable,
          enabled: true,
          focusable: true,
          focused:
              semanticFocus &&
              focusNode.hasFocus &&
              selected?.start.path.equals(node.path) == true,
          multiline: true,
          readOnly: !editable,
          label: _label(node),
          value: plain,
          onTap: focusFromSemantics,
          onFocus: focusFromSemantics,
          onSetSelection: (selection) =>
              editor.service.selectionService.updateSelection(
                Selection.single(
                  path: node.path,
                  startOffset: selection.start,
                  endOffset: selection.end,
                ),
              ),
          onSetText: editable
              ? (next) => unawaited(replaceAccessibleText(editor, node, next))
              : null,
          child: widget.child,
        );
      },
    );
  }
}

String _label(Node node) => switch (node.type) {
  'heading' => 'Heading ${node.attributes['level']}',
  'm09_toggle' => 'Toggle text',
  'm09_callout' => 'Callout text',
  'quote' => 'Quote text',
  _ => 'Text block',
};

Future<void> replaceAccessibleText(
  EditorState editor,
  Node node,
  String text,
) async {
  final old = node.delta;
  if (old == null || old.toPlainText() == text) return;
  // Diff plain text only; composing it onto the rich delta keeps unaffected
  // style/math spans. One engine transaction supplies one undo operation.
  final change = (Delta()..insert(old.toPlainText())).diff(
    Delta()..insert(text),
  );
  final transaction = editor.transaction
    ..updateNode(node, {'delta': old.compose(change).toJson()});
  transaction.afterSelection = Selection.collapsed(
    Position(path: node.path, offset: text.length),
  );
  await editor.apply(transaction);
}
