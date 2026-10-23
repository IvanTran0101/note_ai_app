import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';

import 'rich_editor_adapter.dart';
import 'block_insert_anchor.dart';

/// Layout positions the margin control and its semantics in the same space.
/// Paint-only follower transforms can leave Web click regions over the text.
final class BlockInsertGutter extends StatefulWidget {
  const BlockInsertGutter({
    super.key,
    required this.node,
    required this.adapter,
    required this.onAdd,
    required this.child,
  });
  final engine.Node node;
  final RichEditorAdapter adapter;
  final VoidCallback onAdd;
  final Widget child;
  @override
  State<BlockInsertGutter> createState() => _BlockInsertGutterState();
}

final class _BlockInsertGutterState extends State<BlockInsertGutter> {
  final _targetKey = GlobalKey();
  final _portal = OverlayPortalController();
  Timer? _leave;
  bool _hovered = false, _overButton = false;
  bool _routeCurrent = true;
  String get _id => widget.node.attributes['m09_id'] as String;

  bool get _selected {
    final selection = widget.adapter.editor.selection;
    return selection != null &&
        selection.start.path.length == widget.node.path.length &&
        List.generate(
          widget.node.path.length,
          (i) => widget.node.path[i] == selection.start.path[i],
        ).every((same) => same);
  }

  @override
  void initState() {
    super.initState();
    widget.adapter.addListener(_changed);
    widget.adapter.gutterHover.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    _changed();
  }

  @override
  void didUpdateWidget(covariant BlockInsertGutter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adapter != widget.adapter) {
      oldWidget.adapter.removeListener(_changed);
      oldWidget.adapter.gutterHover.removeListener(_changed);
      widget.adapter.addListener(_changed);
      widget.adapter.gutterHover.addListener(_changed);
    }
    _changed();
  }

  void _changed() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final visible =
          _routeCurrent &&
          widget.adapter.editable &&
          (widget.adapter.gutterHover.value == _id ||
              widget.adapter.gutterHover.value == null && _selected);
      if (!visible) {
        _hide();
      } else {
        if (!_portal.isShowing) _portal.show();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Widget _button(BuildContext context, OverlayChildLayoutInfo info) {
    final target = _targetKey.currentContext?.findRenderObject();
    if (target is! RenderBox || !target.hasSize) return const SizedBox.shrink();
    final point = MatrixUtils.transformPoint(
      info.childPaintTransform,
      blockInsertAnchor(widget.node, target),
    );
    return Positioned(
      left: point.dx,
      top: point.dy,
      child: MouseRegion(
        onEnter: (_) {
          _leave?.cancel();
          _overButton = true;
          widget.adapter.gutterHover.value = _id;
        },
        onExit: (_) {
          _overButton = false;
          _scheduleLeave();
        },
        child: Material(
          color: Colors.transparent,
          child: MergeSemantics(
            child: Semantics(
              label: 'Add block below',
              child: SizedBox.square(
                dimension: 26,
                child: IconButton(
                  key: ValueKey(
                    'block-add-${widget.node.attributes['m09_id']}',
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 26,
                    height: 26,
                  ),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(
                    Icons.add,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onPressed: widget.adapter.editable
                      ? () {
                          _hide();
                          widget.onAdd();
                        }
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _scheduleLeave() {
    _leave?.cancel();
    _leave = Timer(const Duration(milliseconds: 120), () {
      if (!_hovered &&
          !_overButton &&
          widget.adapter.gutterHover.value == _id) {
        widget.adapter.gutterHover.value = null;
      }
      _changed();
    });
  }

  void _hover(PointerEvent event) {
    final target = _targetKey.currentContext?.findRenderObject();
    if (target is! RenderBox || !target.hasSize) return;
    final line = blockInsertLine(widget.node, target).inflate(4);
    final local = target.globalToLocal(event.position);
    // A container includes its descendants; only its first line owns its +.
    _hovered = local.dy >= line.top && local.dy <= line.bottom;
    if (_hovered) {
      _leave?.cancel();
      widget.adapter.gutterHover.value = _id;
    } else {
      _scheduleLeave();
    }
  }

  void _hide() {
    if (_portal.isShowing) _portal.hide();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    child: OverlayPortal.overlayChildLayoutBuilder(
      overlayLocation: OverlayChildLocation.rootOverlay,
      controller: _portal,
      overlayChildBuilder: _button,
      child: MouseRegion(
        key: _targetKey,
        onEnter: _hover,
        onHover: _hover,
        onExit: (_) {
          _hovered = false;
          _scheduleLeave();
        },
        child: widget.child,
      ),
    ),
  );

  @override
  void dispose() {
    _leave?.cancel();
    widget.adapter.removeListener(_changed);
    widget.adapter.gutterHover.removeListener(_changed);
    if (widget.adapter.active.value &&
        widget.adapter.gutterHover.value == _id) {
      widget.adapter.gutterHover.value = null;
    }
    super.dispose();
  }
}
