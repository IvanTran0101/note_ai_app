import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_localizations.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_native_search_empty.dart';
import 'package:note_ai_app/presentation/notes/notes_theme_tokens.dart';
import 'package:note_ai_app/presentation/workspace/workspace_ui_tokens.dart';

void main() {
  testWidgets('centers existing copy and exposes one clear action', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      var clearCalls = 0;
      await _pumpLayout(
        tester,
        viewport: const Size(480, 720),
        onClear: () => clearCalls++,
      );

      final Rect messageRect = tester.getRect(find.text('No matching notes'));
      expect(messageRect.center.dx, closeTo(240, 1));
      expect(messageRect.top, closeTo(60, 1));

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

  testWidgets('keeps clear reachable in the parent scroll at 200 percent', (
    WidgetTester tester,
  ) async {
    var clearCalls = 0;
    await _pumpLayout(
      tester,
      viewport: const Size(320, 180),
      textScale: 2,
      locale: const Locale('vi'),
      parentScroll: true,
      onClear: () => clearCalls++,
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
    final Finder clearAction = find.byKey(
      const ValueKey<String>('dashboard-clear-search-action'),
    );
    expect(tester.getRect(clearAction).bottom, greaterThan(180));

    await tester.ensureVisible(clearAction);
    await tester.pumpAndSettle();
    final Rect visibleAction = tester.getRect(clearAction);
    expect(visibleAction.top, greaterThanOrEqualTo(0));
    expect(visibleAction.bottom, lessThanOrEqualTo(180));
    await tester.tap(clearAction);
    await tester.pump();

    expect(clearCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses workspace secondary text color in light and dark themes', (
    WidgetTester tester,
  ) async {
    for (final Brightness brightness in <Brightness>[
      Brightness.light,
      Brightness.dark,
    ]) {
      await _pumpLayout(
        tester,
        viewport: const Size(480, 720),
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
  Brightness brightness = Brightness.light,
  double textScale = 1,
  Locale locale = const Locale('en'),
  bool parentScroll = false,
  VoidCallback? onClear,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
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
          final DashboardNativeSearchEmpty emptyState =
              DashboardNativeSearchEmpty(
                copy: DashboardCopy.of(context),
                onClear: onClear ?? () {},
              );
          final Widget content = parentScroll
              ? SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const SizedBox(height: 100),
                      const SizedBox(height: NoteFlowSpacing.lg),
                      emptyState,
                    ],
                  ),
                )
              : emptyState;

          return MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(body: content),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}
