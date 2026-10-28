import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_search_viewport.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_localizations.dart';
import 'package:note_ai_app/presentation/workspace/workspace_ui_tokens.dart';

void main() {
  testWidgets('centers the existing empty state in the remaining viewport', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      var clearCalls = 0;
      await _pumpLayout(
        tester,
        viewport: const Size(600, 600),
        headerHeight: 100,
        onClear: () => clearCalls++,
      );

      final Rect emptyStateRect = tester.getRect(
        find.byKey(const ValueKey<String>('dashboard-filtered-empty')),
      );
      expect(emptyStateRect.center.dx, closeTo(300, 1));
      expect(emptyStateRect.center.dy, closeTo(350, 1));

      final Finder clearAction = find.byKey(
        const ValueKey<String>('dashboard-clear-search-action'),
      );
      expect(tester.getSize(clearAction).height, greaterThanOrEqualTo(48));
      expect(find.bySemanticsLabel('Clear search'), findsOneWidget);
      expect(
        tester
            .getSemantics(clearAction)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      await tester.tap(clearAction);
      await tester.pump();
      expect(clearCalls, 1);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('keeps the clear action reachable at 200 percent text scale', (
    WidgetTester tester,
  ) async {
    var clearCalls = 0;
    await _pumpLayout(
      tester,
      viewport: const Size(320, 180),
      headerHeight: 140,
      textScale: 2,
      onClear: () => clearCalls++,
    );

    final Finder clearAction = find.byKey(
      const ValueKey<String>('dashboard-clear-search-action'),
    );
    expect(clearAction, findsOneWidget);
    expect(tester.takeException(), isNull);

    expect(tester.getRect(clearAction).bottom, greaterThan(180));
    await tester.ensureVisible(clearAction);
    await tester.pumpAndSettle();
    final Rect actionRect = tester.getRect(clearAction);
    expect(actionRect.top, greaterThanOrEqualTo(0));
    expect(actionRect.bottom, lessThanOrEqualTo(180));
    await tester.tap(clearAction);
    await tester.pump();

    expect(clearCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses the workspace secondary text color in both themes', (
    WidgetTester tester,
  ) async {
    for (final Brightness brightness in <Brightness>[
      Brightness.light,
      Brightness.dark,
    ]) {
      await _pumpLayout(
        tester,
        viewport: const Size(600, 600),
        headerHeight: 100,
        brightness: brightness,
      );

      final Text message = tester.widget<Text>(find.text('No matching notes'));
      final Color expectedColor = brightness == Brightness.dark
          ? NoteFlowWorkspaceTokens.dark().textSecondary
          : NoteFlowWorkspaceTokens.light().textSecondary;
      expect(message.style?.fontSize, 14);
      expect(message.style?.color, expectedColor);
      expect(tester.takeException(), isNull);
    }
  });
}

Future<void> _pumpLayout(
  WidgetTester tester, {
  required Size viewport,
  required double headerHeight,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  VoidCallback? onClear,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        DashboardCopy.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        brightness: brightness,
        useMaterial3: true,
        visualDensity: VisualDensity.compact,
      ),
      home: Builder(
        builder: (BuildContext context) {
          final Widget layout = DashboardSearchViewport(
            header: SizedBox(
              height: headerHeight,
              child: const Center(child: Text('Search and filter controls')),
            ),
            centerBody: true,
            body: DashboardSearchEmptyState(
              copy: DashboardCopy.of(context),
              onClear: onClear ?? () {},
            ),
          );
          return MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(body: layout),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}
