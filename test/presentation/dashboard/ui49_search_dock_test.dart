import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_localizations.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_search_dock.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_view_models.dart';

void main() {
  testWidgets('native clear remains tappable under compact visual density', (
    WidgetTester tester,
  ) async {
    final TargetPlatform? previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final TextEditingController controller = TextEditingController(
      text: 'search term',
    );
    try {
      var clearCalls = 0;
      await _pumpDock(
        tester,
        viewport: const Size(360, 780),
        controller: controller,
        onClear: () => clearCalls++,
        visualDensity: VisualDensity.compact,
      );

      final Finder clearAction = find.byKey(
        const ValueKey<String>('dashboard-clear-search-field'),
      );
      expect(clearAction, findsOneWidget);
      expect(find.byIcon(kIsWeb ? Icons.clear : Icons.cancel), findsOneWidget);
      expect(tester.getSize(clearAction).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(clearAction).height, greaterThanOrEqualTo(48));
      expect(
        find.byKey(const ValueKey<String>('search-field')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('search-sort')), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('search-close')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey<String>('search-field')),
            )
            .controller,
        same(controller),
      );

      await tester.tap(clearAction);
      await tester.pump();
      expect(clearCalls, 1);
      expect(tester.takeException(), isNull);
    } finally {
      try {
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        controller.dispose();
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    }
  });

  testWidgets('hides clear for an empty query and keeps existing dock keys', (
    WidgetTester tester,
  ) async {
    final TargetPlatform? previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final TextEditingController controller = TextEditingController();
    try {
      await _pumpDock(
        tester,
        viewport: const Size(360, 780),
        controller: controller,
        visualDensity: VisualDensity.compact,
      );

      expect(
        find.byKey(const ValueKey<String>('search-field')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('search-sort')), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('search-close')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('dashboard-clear-search-field')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    } finally {
      try {
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        controller.dispose();
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    }
  });

  testWidgets('keeps the original clear icon in compact non-native layouts', (
    WidgetTester tester,
  ) async {
    final TargetPlatform? previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final TextEditingController controller = TextEditingController(
      text: 'search term',
    );
    try {
      await _pumpDock(
        tester,
        viewport: const Size(390, 844),
        controller: controller,
        visualDensity: VisualDensity.compact,
      );

      final Finder clearAction = find.byKey(
        const ValueKey<String>('dashboard-clear-search-field'),
      );
      expect(find.byIcon(Icons.clear), findsOneWidget);
      expect(find.byIcon(Icons.cancel), findsNothing);
      expect(tester.getSize(clearAction).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(clearAction).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    } finally {
      try {
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        controller.dispose();
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    }
  });
}

Future<void> _pumpDock(
  WidgetTester tester, {
  required Size viewport,
  required TextEditingController controller,
  VisualDensity visualDensity = VisualDensity.standard,
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
      theme: ThemeData(useMaterial3: true, visualDensity: visualDensity),
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: DashboardSearchDock(
            copy: DashboardCopy.of(context),
            controller: controller,
            sort: DashboardSort.updated,
            onChanged: (_) {},
            onClear: onClear ?? () {},
            onSortChanged: (_) {},
            onClose: () {},
            fieldKey: const ValueKey<String>('search-field'),
            sortKey: const ValueKey<String>('search-sort'),
            closeKey: const ValueKey<String>('search-close'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
