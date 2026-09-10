import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/presentation/notes/responsive_notes_workspace.dart';

void main() {
  Widget buildWorkspace({
    required bool hasSelection,
    VoidCallback? onCompactBack,
  }) {
    return MaterialApp(
      home: ResponsiveNotesWorkspace(
        list: const ColoredBox(
          key: ValueKey<String>('test-list'),
          color: Colors.blue,
          child: Center(child: Text('List')),
        ),
        detail: const ColoredBox(
          key: ValueKey<String>('test-detail'),
          color: Colors.green,
          child: Center(child: Text('Detail')),
        ),
        hasSelection: hasSelection,
        onCompactBack: onCompactBack,
      ),
    );
  }

  Future<void> pumpAt(
    WidgetTester tester,
    Size size, {
    bool hasSelection = true,
    VoidCallback? onCompactBack,
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

  testWidgets('medium uses a bounded list pane and expanded detail pane', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(700, 800));

    expect(find.byKey(ResponsiveNotesWorkspace.mediumKey), findsOneWidget);
    expect(find.byKey(ResponsiveNotesWorkspace.listPaneKey), findsOneWidget);
    expect(find.byKey(ResponsiveNotesWorkspace.detailPaneKey), findsOneWidget);
    expect(
      tester.getSize(find.byKey(ResponsiveNotesWorkspace.listPaneKey)).width,
      lessThan(700),
    );
  });

  testWidgets('expanded keeps a stable Notion-like list/detail split', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(1024, 700));

    expect(find.byKey(ResponsiveNotesWorkspace.expandedKey), findsOneWidget);
    expect(
      tester.getSize(find.byKey(ResponsiveNotesWorkspace.listPaneKey)).width,
      336,
    );
    expect(tester.takeException(), isNull);
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
