import 'package:appflowy_editor/src/flutter/scrollable_helpers.dart' as engine;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final axis in Axis.values) {
    for (final reverse in [false, true]) {
      for (final displacement in [-80.25, -0.25, 0.0, 0.25, 80.25]) {
        _testScroll(axis, reverse, displacement);
      }
      _testScroll(axis, reverse, 80, stalled: true);
    }
  }
}

void _testScroll(
  Axis axis,
  bool reverse,
  double displacement, {
  bool stalled = false,
}) {
  testWidgets(
    'oversized caret $axis reverse=$reverse at $displacement stalled=$stalled',
    (tester) async {
      final controller = stalled
          ? _NoMoveController()
          : ScrollController(initialScrollOffset: 400);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: axis == Axis.vertical ? 300 : 80,
                height: axis == Axis.vertical ? 80 : 300,
                child: SingleChildScrollView(
                  controller: controller,
                  scrollDirection: axis,
                  reverse: reverse,
                  child: const SizedBox(width: 2000, height: 2000),
                ),
              ),
            ),
          ),
        ),
      );
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      final offsets = <double>[];
      late final engine.EdgeDraggingAutoScroller scroller;
      scroller = engine.EdgeDraggingAutoScroller(
        scrollable,
        velocityScalar: 7,
        onScrollViewScrolled: () {
          offsets.add(controller.offset);
          // Bound the old infinite microtask loop so a regression fails safely.
          if (offsets.length == 12) scroller.stopAutoScroll();
        },
      );
      scroller.startAutoScrollIfNecessary(
        Rect.fromCenter(
          center:
              viewport.center +
              (axis == Axis.vertical
                  ? Offset(0, displacement)
                  : Offset(displacement, 0)),
          width: 200,
          height: 200,
        ),
        duration: Duration.zero,
      );
      await tester.pumpAndSettle();
      expect(offsets.length, lessThan(12), reason: '$offsets');
      expect(scroller.scrolling, isFalse);
      expect(
        controller.offset,
        closeTo(stalled ? 400 : 400 + displacement * (reverse ? -1 : 1), 0.001),
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}

class _NoMoveController extends ScrollController {
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _NoMovePosition(
    physics: physics,
    context: context,
    initialPixels: 400,
    oldPosition: oldPosition,
  );
}

class _NoMovePosition extends ScrollPositionWithSingleContext {
  _NoMovePosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.oldPosition,
  });

  @override
  Future<void> moveTo(
    double to, {
    Duration? duration,
    Curve? curve,
    bool? clamp = true,
  }) async {}
}
