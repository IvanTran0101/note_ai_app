import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';

import 'rich_editor_adapter.dart';

/// A follower occupies the reading column's margin without moving its text.
/// The overlay has its own hit region, including outside the block's bounds.
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
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  Timer? _leave;
  bool _hovered = false, _overButton = false;
  bool _routeCurrent = true;

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
      widget.adapter.addListener(_changed);
    }
    _changed();
  }

  void _changed() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final visible =
          _routeCurrent &&
          widget.adapter.editable &&
          (_hovered || _overButton || _selected);
      if (!visible) {
        _hide();
      } else if (!_portal.isShowing) {
        _portal.show();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Widget _button(BuildContext context) => Positioned(
    left: 0,
    top: 0,
    child: CompositedTransformFollower(
      link: _link,
      showWhenUnlinked: false,
      offset: const Offset(-28, 0),
      child: MouseRegion(
        onEnter: (_) {
          _leave?.cancel();
          _overButton = true;
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
    ),
  );

  void _scheduleLeave() {
    _leave?.cancel();
    _leave = Timer(const Duration(milliseconds: 120), _changed);
  }

  void _hide() {
    if (_portal.isShowing) _portal.hide();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    child: OverlayPortal(
      overlayLocation: OverlayChildLocation.rootOverlay,
      controller: _portal,
      overlayChildBuilder: _button,
      child: CompositedTransformTarget(
        link: _link,
        child: MouseRegion(
          onEnter: (_) {
            _leave?.cancel();
            _hovered = true;
            _changed();
          },
          onExit: (_) {
            _hovered = false;
            _scheduleLeave();
          },
          child: widget.child,
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _leave?.cancel();
    widget.adapter.removeListener(_changed);
    super.dispose();
  }
}
