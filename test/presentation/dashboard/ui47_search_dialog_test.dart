import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_search_dialog.dart';

void main() {
  const surface = ValueKey('search-surface');
  final measurements = [
    (size: const Size(1280, 720), left: 340.0, top: 64.8, height: 639.2),
    (size: const Size(1280, 900), left: 340.0, top: 81.0, height: 700.0),
    (size: const Size(1480, 1000), left: 440.0, top: 90.0, height: 700.0),
    (size: const Size(500, 900), left: 0.0, top: 81.0, height: 700.0),
  ];
  for (final measurement in measurements) {
    testWidgets('UI47 matches reference placement at ${measurement.size}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(
        measurement.size.width,
        measurement.size.height + 20,
      );
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const SizedBox(height: 20),
                Expanded(
                  child: DashboardSearchDialog(
                    surfaceKey: surface,
                    builder: (_, _) =>
                        ListView(children: const [Text('Existing results')]),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bounds = tester.getRect(find.byKey(surface));
      final narrow = measurement.size.width == 500;
      expect(
        bounds.left,
        closeTo(!kIsWeb && narrow ? 24 : measurement.left, 0.1),
      );
      expect(bounds.width, closeTo(narrow ? (kIsWeb ? 500 : 452) : 600, 0.1));
      expect(bounds.top - 20, closeTo(kIsWeb ? measurement.top : 60, 0.1));
      final nativeHeight = measurement.size.height == 720 ? 640.0 : 704.0;
      expect(
        bounds.height,
        closeTo(kIsWeb ? measurement.height : nativeHeight, 0.1),
      );
      expect(find.text('Existing results'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'UI47 short Search stays clear of IME and inside horizontal edges',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 400);
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            resizeToAvoidBottomInset: false,
            body: DashboardSearchDialog(
              surfaceKey: surface,
              builder: (_, _) =>
                  ListView(children: const [Text('Existing results')]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bounds = tester.getRect(find.byKey(surface));
      expect(bounds.left, greaterThanOrEqualTo(32));
      expect(bounds.right, lessThanOrEqualTo(768));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.bottom, lessThanOrEqualTo(200));
      expect(bounds.height, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );
}
