import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Host accessibility actions delegate to the same editor transaction engine.
Widget accessibleBlock(
  BuildContext context, {
  required Node node,
  required Widget child,
  required EditorState editor,
  required bool editable,
  required FocusNode focusNode,
  ValueListenable<bool>? inputSuspended,
}) {
  final delta = node.delta;
  if (delta == null) return child;
  return _AccessibleBlock(
    node: node,
    editor: editor,
    editable: editable,
    focusNode: focusNode,
    inputSuspended: inputSuspended,
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
    this.inputSuspended,
  });
  final Node node;
  final EditorState editor;
  final bool editable;
  final FocusNode focusNode;
  final Widget child;
  final ValueListenable<bool>? inputSuspended;
  @override
  State<_AccessibleBlock> createState() => _AccessibleBlockState();
}

class _AccessibleBlockState extends State<_AccessibleBlock> {
  final blockFocus = FocusNode(debugLabel: 'Document text block');
  bool semanticFocus = false;
  bool activating = false;
  bool get _inputSuspended => widget.inputSuspended?.value ?? false;

  @override
  void initState() {
    super.initState();
    widget.editor.selectionNotifier.addListener(selectionChanged);
    widget.inputSuspended?.addListener(_inputOwnershipChanged);
    // A conversion replaces the selected node at the same path. Its selection
    // can be committed before the new semantic field mounts; activate that
    // field after layout so typing continues without a second click.
    WidgetsBinding.instance.addPostFrameCallback((_) => selectionChanged());
  }

  @override
  void dispose() {
    widget.editor.selectionNotifier.removeListener(selectionChanged);
    widget.inputSuspended?.removeListener(_inputOwnershipChanged);
    blockFocus.dispose();
    super.dispose();
  }

  void selectionChanged() {
    if (!mounted || activating || !widget.editable || _inputSuspended) return;
    if (semanticFocus && (!kIsWeb || blockFocus.hasPrimaryFocus)) return;
    if (widget.editor.selection?.start.path.equals(widget.node.path) == true) {
      unawaited(focusFromSemantics());
    }
  }

  void _inputOwnershipChanged() {
    if (_inputSuspended) return;
    // The query's TextField is still mounted during close(). Focus it releases
    // on disposal would otherwise replace the block focus we just restored.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Timer.run(() {
        if (!mounted ||
            _inputSuspended ||
            !_selected ||
            !(ModalRoute.of(context)?.isCurrent ?? true)) {
          return;
        }
        final primary = FocusManager.instance.primaryFocus;
        if (primary is FocusScopeNode ||
            primary == blockFocus ||
            primary == widget.focusNode) {
          unawaited(focusFromSemantics());
        }
      });
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool get _selected =>
      !widget.editor.isDisposed &&
      widget.editor.selection?.start.path.equals(widget.node.path) == true;

  Future<void> focusFromSemantics() async {
    if (!mounted ||
        widget.editor.isDisposed ||
        !widget.editable ||
        _inputSuspended ||
        activating) {
      return;
    }
    if (semanticFocus &&
        (kIsWeb ? blockFocus.hasPrimaryFocus : widget.focusNode.hasFocus) &&
        _selected) {
      if (kIsWeb) await _reactivateSemanticInput();
      return;
    }
    activating = true;
    final selection = widget.editor.selection;
    if (selection?.start.path.equals(widget.node.path) != true) {
      widget.editor.service.selectionService.updateSelection(
        Selection.collapsed(
          Position(path: widget.node.path, offset: widget.node.delta!.length),
        ),
      );
    }
    try {
      // Web clicks keep their native field attached, so immediate typing is
      // safe. Native waits for a converted block to finish mounting.
      if (!kIsWeb) await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !widget.editable || !_selected || _inputSuspended) return;
      // The engine's keyboard focus is an ancestor. Each Web field owns the
      // primary focus, so its wrapper cannot take DOM focus from the textarea.
      await Future<void>.value();
      if (!mounted || !widget.editable || !_selected || _inputSuspended) return;
      // A title/dialog may have replaced the platform input client without
      // changing this block's selection. Reattach through the public service.
      if (kIsWeb) {
        widget.editor.service.keyboardService?.enableKeyBoard(
          widget.editor.selection!,
        );
      }
      (kIsWeb ? blockFocus : widget.focusNode).requestFocus();
      await Future<void>.value();
      if (mounted &&
          widget.editable &&
          !_inputSuspended &&
          _selected &&
          widget.focusNode.hasFocus) {
        setState(() => semanticFocus = true);
      }
    } finally {
      activating = false;
    }
  }

  /// A DOM focus replay needs a fresh focused semantics update so the Web
  /// engine activates the field's input handlers again after ancestor movement.
  Future<void> _reactivateSemanticInput() async {
    activating = true;
    try {
      setState(() => semanticFocus = false);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          !widget.editable ||
          _inputSuspended ||
          !_selected ||
          !blockFocus.hasPrimaryFocus) {
        return;
      }
      widget.editor.service.keyboardService?.enableKeyBoard(
        widget.editor.selection!,
      );
      setState(() => semanticFocus = true);
    } finally {
      activating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final editor = widget.editor;
    final focusNode = widget.focusNode;
    final editable = widget.editable;
    final field = ListenableBuilder(
      listenable: Listenable.merge([
        node,
        editor.selectionNotifier,
        focusNode,
        blockFocus,
        if (widget.inputSuspended != null) widget.inputSuspended!,
      ]),
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
              !_inputSuspended &&
              semanticFocus &&
              (kIsWeb ? blockFocus.hasPrimaryFocus : focusNode.hasFocus) &&
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
    return kIsWeb
        ? Focus(
            focusNode: blockFocus,
            includeSemantics: false,
            skipTraversal: true,
            child: field,
          )
        : field;
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
