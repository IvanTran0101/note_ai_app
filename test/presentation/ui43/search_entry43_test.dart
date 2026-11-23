import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_localizations.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_search_dock.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_state_views.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_view_models.dart';

void main() {
  group('UI43 search entry and dashboard states', () {
    testWidgets('compact search dock fits narrow width at large text scale', (
      WidgetTester tester,
    ) async {
      final DashboardCopy copy = await DashboardCopy.delegate.load(
        const Locale('en'),
      );
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);

      for (final Brightness brightness in <Brightness>[
        Brightness.light,
        Brightness.dark,
      ]) {
        await _pump(
          tester,
          body: const SizedBox.shrink(),
          size: const Size(320, 640),
          textScale: 2,
          brightness: brightness,
          bottomNavigationBar: DashboardSearchDock(
            copy: copy,
            controller: controller,
            sort: DashboardSort.updated,
            onChanged: (_) {},
            onClear: controller.clear,
            onSortChanged: (_) {},
            onClose: () {},
            fieldKey: const ValueKey<String>('search-entry-field'),
            sortKey: const ValueKey<String>('search-entry-sort'),
            closeKey: const ValueKey<String>('search-entry-close'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester
              .getSize(find.byKey(const ValueKey<String>('search-entry-field')))
              .height,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester
              .getSize(find.byKey(const ValueKey<String>('search-entry-sort')))
              .height,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester
              .getSize(find.byKey(const ValueKey<String>('search-entry-close')))
              .width,
          greaterThanOrEqualTo(48),
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('empty states keep create and clear actions at 200% scale', (
      WidgetTester tester,
    ) async {
      final DashboardCopy copy = await DashboardCopy.delegate.load(
        const Locale('en'),
      );
      bool cleared = false;
      await _pump(
        tester,
        body: DashboardFilteredEmptyView(
          copy: copy,
          onClear: () => cleared = true,
        ),
        size: const Size(320, 640),
        textScale: 2,
        brightness: Brightness.dark,
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .getSize(
              find.byKey(
                const ValueKey<String>('dashboard-clear-search-action'),
              ),
            )
            .height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('dashboard-clear-search-action')),
      );
      expect(cleared, isTrue);

      bool created = false;
      await _pump(
        tester,
        body: DashboardEmptyView(
          copy: copy,
          onCreateNote: () => created = true,
        ),
        size: const Size(320, 640),
        textScale: 2,
        brightness: Brightness.light,
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .getSize(
              find.byKey(const ValueKey<String>('dashboard-empty-create')),
            )
            .height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('dashboard-empty-create')),
      );
      expect(created, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('error retry actions stack for large text in both themes', (
      WidgetTester tester,
    ) async {
      final DashboardCopy copy = await DashboardCopy.delegate.load(
        const Locale('en'),
      );

      for (final Brightness brightness in <Brightness>[
        Brightness.light,
        Brightness.dark,
      ]) {
        bool retried = false;
        await _pump(
          tester,
          body: DashboardErrorView(copy: copy, onRetry: () => retried = true),
          size: const Size(560, 640),
          textScale: 2,
          brightness: brightness,
        );
        await tester.pumpAndSettle();

        final Rect messageRect = tester.getRect(find.text(copy.loadError));
        final Rect retryRect = tester.getRect(
          find.byKey(const ValueKey<String>('dashboard-retry')),
        );
        expect(retryRect.top, greaterThanOrEqualTo(messageRect.bottom));
        await tester.tap(find.byKey(const ValueKey<String>('dashboard-retry')));
        expect(retried, isTrue);
        expect(tester.takeException(), isNull);

        bool inlineRetried = false;
        await _pump(
          tester,
          body: DashboardInlineError(
            copy: copy,
            onRetry: () => inlineRetried = true,
          ),
          size: const Size(560, 400),
          textScale: 2,
          brightness: brightness,
        );
        await tester.pumpAndSettle();

        final Rect inlineMessageRect = tester.getRect(
          find.text(copy.loadError),
        );
        final Rect inlineRetryRect = tester.getRect(
          find.byKey(const ValueKey<String>('dashboard-retry')),
        );
        expect(
          inlineRetryRect.top,
          greaterThanOrEqualTo(inlineMessageRect.bottom),
        );
        await tester.tap(find.byKey(const ValueKey<String>('dashboard-retry')));
        expect(inlineRetried, isTrue);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('loading placeholder remains bounded on a compact screen', (
      WidgetTester tester,
    ) async {
      final DashboardCopy copy = await DashboardCopy.delegate.load(
        const Locale('en'),
      );

      await _pump(
        tester,
        body: DashboardLoadingView(copy: copy),
        size: const Size(320, 568),
        textScale: 2,
        brightness: Brightness.dark,
      );
      await tester.pumpAndSettle();

      expect(find.byType(DashboardLoadingView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required Widget body,
  Widget? bottomNavigationBar,
  Size size = const Size(1200, 800),
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: ThemeData(
        brightness: brightness,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF236BB3),
          brightness: brightness,
        ),
      ),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        DashboardCopy.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          devicePixelRatio: 1,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(body: body, bottomNavigationBar: bottomNavigationBar),
      ),
    ),
  );
}
