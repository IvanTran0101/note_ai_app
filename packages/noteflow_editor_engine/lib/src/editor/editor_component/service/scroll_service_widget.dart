import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/editor_component/service/scroll/desktop_scroll_service.dart';
import 'package:appflowy_editor/src/editor/editor_component/service/scroll/mobile_scroll_service.dart';
import 'package:appflowy_editor/src/editor/toolbar/mobile/utils/keyboard_height_observer.dart';
import 'package:appflowy_editor/src/editor/util/platform_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ScrollServiceWidget extends StatefulWidget {
  const ScrollServiceWidget({
    super.key,
    required this.editorScrollController,
    required this.child,
  });

  final EditorScrollController editorScrollController;

  final Widget child;

  @override
  State<ScrollServiceWidget> createState() => _ScrollServiceWidgetState();
}

class _ScrollServiceWidgetState extends State<ScrollServiceWidget>
    implements AppFlowyScrollService {
  final _forwardKey =
      GlobalKey(debugLabel: 'forward_to_platform_scroll_service');
  late AppFlowyScrollService forward =
      _forwardKey.currentState as AppFlowyScrollService;

  late EditorState editorState = context.read<EditorState>();

  @override
  late ScrollController scrollController = ScrollController();

  Selection? lastSelection;
  Size? _lastViewportSize;
  int _scrollRequestGeneration = 0;

  @override
  void initState() {
    super.initState();
    editorState.selectionNotifier.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _scrollRequestGeneration++;
    editorState.selectionNotifier.removeListener(_onSelectionChanged);
    editorState.autoScroller?.stopAutoScroll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = constraints.biggest;
        final previousViewportSize = _lastViewportSize;
        _lastViewportSize = viewportSize;

        if (previousViewportSize != null &&
            previousViewportSize != viewportSize) {
          _requestSelectionScroll(stopCurrentScroll: true);
        }

        return Provider.value(
          value: widget.editorScrollController,
          child: Builder(
            builder: (context) {
              if (PlatformExtension.isDesktopOrWeb) {
                return _buildDesktopScrollService(context);
              } else if (PlatformExtension.isMobile) {
                return _buildMobileScrollService(context);
              }
              throw UnimplementedError();
            },
          ),
        );
      },
    );
  }

  Widget _buildDesktopScrollService(
    BuildContext context,
  ) {
    return DesktopScrollService(
      key: _forwardKey,
      child: widget.child,
    );
  }

  Widget _buildMobileScrollService(
    BuildContext context,
  ) {
    return MobileScrollService(
      key: _forwardKey,
      child: widget.child,
    );
  }

  void _onSelectionChanged() {
    _requestSelectionScroll();
  }

  void _requestSelectionScroll({bool stopCurrentScroll = false}) {
    final requestGeneration = ++_scrollRequestGeneration;
    // should auto scroll after the cursor or selection updated.
    final selection = editorState.selection;
    if (selection == null ||
        [SelectionUpdateReason.selectAll]
            .contains(editorState.selectionUpdateReason)) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || requestGeneration != _scrollRequestGeneration) {
        return;
      }
      if (stopCurrentScroll) {
        editorState.autoScroller?.stopAutoScroll();
      }

      // For desktop: if auto-scroller is already scrolling (from drag-to-select),
      // don't override it here. The desktop_selection_service handles drag scrolling.
      if (PlatformExtension.isDesktopOrWeb &&
          (editorState.autoScroller?.scrolling ?? false)) {
        return;
      }

      if (PlatformExtension.isMobile) {
        // soft keyboard
        // workaround: wait for the soft keyboard to show up
        final keyboardDelay = KeyboardHeightObserver.currentKeyboardHeight == 0
            ? const Duration(milliseconds: 250)
            : Duration.zero;

        Future.delayed(keyboardDelay, () {
          if (!mounted ||
              requestGeneration != _scrollRequestGeneration ||
              _forwardKey.currentContext == null) {
            return;
          }
          _scrollCurrentSelection(requestGeneration);
        });
      } else {
        _scrollCurrentSelection(requestGeneration);
      }
    });
    // Requests may arrive while the editor is idle or from a post-frame
    // selection update. A queued callback alone does not schedule another frame.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _scrollCurrentSelection(int requestGeneration) {
    if (!mounted ||
        requestGeneration != _scrollRequestGeneration ||
        _forwardKey.currentContext == null) {
      return;
    }

    final selection = editorState.selection;
    if (selection == null ||
        [SelectionUpdateReason.selectAll]
            .contains(editorState.selectionUpdateReason)) {
      return;
    }

    // Read geometry after the native keyboard resize has settled. A selection
    // rectangle captured before the delay can point at stale screen coordinates.
    final selectionRects = editorState.selectionRects();
    if (selectionRects.isEmpty) {
      return;
    }

    Rect targetRect;
    AxisDirection? direction;
    final dynamic dragMode =
        editorState.selectionExtraInfo?['selection_drag_mode'];
    switch (dragMode?.toString()) {
      case 'MobileSelectionDragMode.leftSelectionHandle':
        targetRect = selectionRects.first;
        direction = AxisDirection.up;
        break;
      case 'MobileSelectionDragMode.rightSelectionHandle':
        targetRect = selectionRects.last;
        direction = AxisDirection.down;
        break;
      default:
        targetRect = selectionRects.last;
        final isInSingleNode = (lastSelection?.isSingle ?? false) &&
            lastSelection?.start.path == selection.start.path;
        if (selection.isForward && isInSingleNode) {
          targetRect = selectionRects.first;
        }
    }

    lastSelection = selection;
    final isDragOperation = dragMode != null &&
        (dragMode.toString() == 'MobileSelectionDragMode.leftSelectionHandle' ||
            dragMode.toString() ==
                'MobileSelectionDragMode.rightSelectionHandle');
    startAutoScroll(
      targetRect.centerRight,
      edgeOffset: editorState.autoScrollEdgeOffset,
      direction: direction,
      duration: PlatformExtension.isMobile && isDragOperation
          ? const Duration(milliseconds: 2)
          : Duration.zero,
    );
  }

  @override
  void disable() => forward.disable();

  @override
  double get dy => forward.dy;

  @override
  void enable() => forward.enable();

  @override
  double get maxScrollExtent => forward.maxScrollExtent;

  @override
  double get minScrollExtent => forward.minScrollExtent;

  @override
  double? get onePageHeight => forward.onePageHeight;

  @override
  int? get page => forward.page;

  @override
  void scrollTo(
    double dy, {
    Duration duration = const Duration(milliseconds: 150),
  }) =>
      forward.scrollTo(dy, duration: duration);

  @override
  void jumpTo(int index) => forward.jumpTo(index);

  @override
  void jumpToTop() {
    forward.jumpToTop();
  }

  @override
  void jumpToBottom() {
    forward.jumpToBottom();
  }

  @override
  void startAutoScroll(
    Offset offset, {
    double edgeOffset = 100,
    AxisDirection? direction,
    Duration? duration,
  }) {
    forward.startAutoScroll(
      offset,
      edgeOffset: edgeOffset,
      direction: direction,
      duration: duration,
    );
  }

  @override
  void stopAutoScroll() => forward.stopAutoScroll();

  @override
  void goBallistic(double velocity) => forward.goBallistic(velocity);
}
