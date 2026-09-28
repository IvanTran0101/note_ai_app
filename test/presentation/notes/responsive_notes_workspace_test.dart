import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/presentation/notes/responsive_notes_workspace.dart';

void main() {
  Widget buildWorkspace({
    required bool hasSelection,
    VoidCallback? onCompactBack,
    Widget? detail,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ResponsiveNotesWorkspace(
          list: const ColoredBox(
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

  testWidgets('compact shows the list when there is no selection', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(390, 844), hasSelection: false);

    expect(find.text('List'), findsOneWidget);
    expect(find.text('Detail'), findsNothing);
  });

  testWidgets('medium gives the selected detail the full page canvas', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(700, 800));

    expect(find.byKey(ResponsiveNotesWorkspace.mediumKey), findsOneWidget);
    expect(find.byKey(ResponsiveNotesWorkspace.detailPaneKey), findsOneWidget);
    expect(find.byKey(ResponsiveNotesWorkspace.listPaneKey), findsNothing);
    expect(find.text('Detail'), findsOneWidget);
    expect(find.text('List'), findsNothing);
  });

  testWidgets('expanded presents the list and detail as separate pages', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(1024, 700));

    expect(find.byKey(ResponsiveNotesWorkspace.expandedKey), findsOneWidget);
    expect(find.byKey(ResponsiveNotesWorkspace.detailPaneKey), findsOneWidget);
    expect(find.byKey(ResponsiveNotesWorkspace.listPaneKey), findsNothing);
    expect(find.text('Detail'), findsOneWidget);
    expect(find.text('List'), findsNothing);
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
}

class _DraftDetail extends StatefulWidget {
  const _DraftDetail();

  static const Key fieldKey = ValueKey<String>('responsive-detail-draft-field');

  @override
  State<_DraftDetail> createState() => _DraftDetailState();
}

class _DraftDetailState extends State<_DraftDetail> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(key: _DraftDetail.fieldKey, controller: _controller);
  }
}
