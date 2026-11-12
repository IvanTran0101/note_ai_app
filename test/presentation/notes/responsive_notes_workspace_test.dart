import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/presentation/notes/responsive_notes_workspace.dart';

void main() {
  Widget buildWorkspace({
    required bool hasSelection,
    VoidCallback? onCompactBack,
    Widget? detail,
    Widget? list,
    VoidCallback? onDismiss,
    bool disableAnimations = false,
    bool preferFullPage = false,
  }) {
    return MaterialApp(
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: Scaffold(
        body: ResponsiveNotesWorkspace(
          preferFullPage: preferFullPage,
          list:
              list ??
              const ColoredBox(
                key: ValueKey<String>('test-list'),
                color: Colors.blue,
                child: Center(child: Text('List')),
              ),
          detail:
              detail ??
              const ColoredBox(
                key: ValueKey<String>('test-detail'),
                color: Colors.green,
                child: Center(child: Text('Detail')),
              ),
          hasSelection: hasSelection,
          onCompactBack: onCompactBack,
          onDismiss: onDismiss,
        ),
      ),
    );
  }

  Future<void> pumpAt(
    WidgetTester tester,
    Size size, {
    bool hasSelection = true,
    VoidCallback? onCompactBack,
    Widget? detail,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: buildWorkspace(
          hasSelection: hasSelection,
          onCompactBack: onCompactBack,
          detail: detail,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('compact shows only the selected detail', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(320, 568));

    expect(find.byKey(ResponsiveNotesWorkspace.compactKey), findsOneWidget);
    expect(find.text('Detail'), findsOneWidget);
    expect(find.text('List'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full page retains the editor across widths and closes safely', (
    tester,
  ) async {
    final controller = TextEditingController();
    final field = TextField(
      key: const ValueKey('full-draft'),
      controller: controller,
    );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpWidget(
      buildWorkspace(hasSelection: true, preferFullPage: true, detail: field),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('full-draft')), 'draft');
    final state = tester.state(find.byKey(const ValueKey('full-draft')));
    for (final size in const [
      Size(1280, 900),
      Size(768, 900),
      Size(390, 844),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(find.byKey(ResponsiveNotesWorkspace.fullPageKey), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(ResponsiveNotesWorkspace.detailPaneKey))
            .width,
        size.width,
      );
      expect(
        tester.state(find.byKey(const ValueKey('full-draft'))),
        same(state),
      );
      expect(controller.text, 'draft');
      expect(find.text('List'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(
      buildWorkspace(hasSelection: false, preferFullPage: true, detail: field),
    );
    await tester.pumpAndSettle();
    expect(find.text('List'), findsOneWidget);
    expect(state.mounted, false);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('compact shows the list when there is no selection', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(390, 844), hasSelection: false);

    expect(find.text('List'), findsOneWidget);
    expect(find.text('Detail'), findsNothing);
  });

  testWidgets('medium opens a center peek over the mounted list', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(700, 800));

    expect(find.byKey(ResponsiveNotesWorkspace.mediumKey), findsOneWidget);
    expect(find.byKey(ResponsiveNotesWorkspace.detailPaneKey), findsOneWidget);
    expect(find.byKey(ResponsiveNotesWorkspace.listPaneKey), findsOneWidget);
    expect(
      find.byKey(ResponsiveNotesWorkspace.dismissBarrierKey),
      findsOneWidget,
    );
    expect(find.text('Detail'), findsOneWidget);
    expect(find.text('List'), findsOneWidget);
  });

  testWidgets(
    'dismiss barrier does not merge a tap action over editor semantics',
    (WidgetTester tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await pumpAt(
          tester,
          const Size(700, 800),
          onCompactBack: () {},
          detail: Semantics(
            container: true,
            label: 'Attachment editor',
            child: const Text('PDF controls'),
          ),
        );
        final barrier = tester.widget<GestureDetector>(
          find.byKey(ResponsiveNotesWorkspace.dismissBarrierKey),
        );
        expect(barrier.excludeFromSemantics, true);
        expect(
          tester
              .getSemantics(find.text('PDF controls'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          false,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('expanded opens a side peek beside the interactive list', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(1024, 700));

    expect(find.byKey(ResponsiveNotesWorkspace.expandedKey), findsOneWidget);
    expect(find.byKey(ResponsiveNotesWorkspace.detailPaneKey), findsOneWidget);
    expect(find.byKey(ResponsiveNotesWorkspace.listPaneKey), findsOneWidget);
    expect(find.text('Detail'), findsOneWidget);
    expect(find.text('List'), findsOneWidget);
    final Rect list = tester.getRect(
      find.byKey(ResponsiveNotesWorkspace.listPaneKey),
    );
    final Rect detail = tester.getRect(
      find.byKey(ResponsiveNotesWorkspace.detailPaneKey),
    );
    expect(detail.left, closeTo(list.right, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('retains detail state when resizing across its breakpoints', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(1024, 700), detail: const _DraftDetail());

    final Finder draft = find.byKey(_DraftDetail.fieldKey);
    await tester.enterText(draft, 'Keep this detail');

    for (final Size size in <Size>[
      const Size(390, 844),
      const Size(700, 800),
      const Size(1024, 700),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(draft).controller!.text,
        'Keep this detail',
      );
    }
  });

  testWidgets('expanded shows the full-width notes list with no selection', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(1280, 800), hasSelection: false);

    expect(find.byKey(ResponsiveNotesWorkspace.listPaneKey), findsOneWidget);
    expect(find.byKey(ResponsiveNotesWorkspace.detailPaneKey), findsNothing);
    expect(find.text('List'), findsOneWidget);
    expect(find.text('Detail'), findsNothing);
  });

  testWidgets('compact back action remains available for selected detail', (
    WidgetTester tester,
  ) async {
    bool backed = false;
    await pumpAt(
      tester,
      const Size(320, 568),
      onCompactBack: () => backed = true,
    );

    await tester.tap(find.byIcon(Icons.arrow_back));
    expect(backed, isTrue);
  });

  testWidgets('center backdrop requests close without activating the list', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(700, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    int closed = 0;
    int selected = 0;
    await tester.pumpWidget(
      buildWorkspace(
        hasSelection: true,
        onDismiss: () => closed++,
        list: GestureDetector(
          onTap: () => selected++,
          child: const Text('List'),
        ),
      ),
    );
    await tester.tapAt(const Offset(8, 100));
    expect(closed, 1);
    expect(selected, 0);
  });

  testWidgets('opening and closing peeks preserves list scroll state', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final Widget list = ListView(
      children: List<Widget>.generate(
        60,
        (int i) => SizedBox(height: 60, child: Text('Row $i')),
      ),
    );
    await tester.pumpWidget(buildWorkspace(hasSelection: false, list: list));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    final ScrollableState before = tester.state(find.byType(Scrollable));
    final double offset = before.position.pixels;
    expect(offset, greaterThan(0));
    for (final bool selected in <bool>[true, false]) {
      await tester.pumpWidget(
        buildWorkspace(hasSelection: selected, list: list),
      );
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(Scrollable)), same(before));
      expect(before.position.pixels, offset);
    }
  });

  testWidgets('closing disposes editor before outgoing shell finishes', (
    WidgetTester tester,
  ) async {
    int disposed = 0;
    await tester.pumpWidget(
      buildWorkspace(
        hasSelection: true,
        detail: _DraftDetail(onDispose: () => disposed++),
      ),
    );
    await tester.pumpWidget(buildWorkspace(hasSelection: false));
    expect(disposed, 1);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduce motion opens peek immediately without animation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildWorkspace(hasSelection: false, disableAnimations: true),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      buildWorkspace(hasSelection: true, disableAnimations: true),
    );
    expect(find.byKey(ResponsiveNotesWorkspace.detailPaneKey), findsOneWidget);
    final AnimationController motion =
        tester
                .widget<AnimatedBuilder>(
                  find
                      .descendant(
                        of: find.byType(ResponsiveNotesWorkspace),
                        matching: find.byType(AnimatedBuilder),
                      )
                      .first,
                )
                .animation
            as AnimationController;
    expect(motion.value, 1);
    expect(motion.isAnimating, isFalse);
    expect(tester.takeException(), isNull);
  });
}

class _DraftDetail extends StatefulWidget {
  const _DraftDetail({this.onDispose});

  final VoidCallback? onDispose;

  static const Key fieldKey = ValueKey<String>('responsive-detail-draft-field');

  @override
  State<_DraftDetail> createState() => _DraftDetailState();
}

class _DraftDetailState extends State<_DraftDetail> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(key: _DraftDetail.fieldKey, controller: _controller);
  }
}
