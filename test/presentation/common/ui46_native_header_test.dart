import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/common/note_flow_page_header.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('page controls clear cutouts and retain targets at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      tester.view.padding = const FakeViewPadding(
        top: 44,
        left: 16,
        right: 24,
        bottom: 34,
      );
      addTearDown(tester.view.reset);
      var back = 0, more = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteFlowPageHeader(
              breadcrumb: '',
              backKey: const ValueKey('back'),
              onBack: () => back++,
              actions: [
                IconButton(
                  key: const ValueKey('more'),
                  onPressed: () => more++,
                  icon: const Icon(Icons.more_horiz),
                ),
              ],
            ),
          ),
        ),
      );
      final backRect = tester.getRect(find.byKey(const ValueKey('back')));
      final moreRect = tester.getRect(find.byKey(const ValueKey('more')));
      final inset = kIsWeb ? 0 : 10;
      expect(backRect.left, 16 + inset);
      expect(moreRect.right, size.width - 24 - inset);
      expect(backRect.top, greaterThanOrEqualTo(44));
      final backTarget = kIsWeb && size.width >= 600 ? 40 : 48;
      expect(backRect.width, greaterThanOrEqualTo(backTarget));
      expect(backRect.height, greaterThanOrEqualTo(backTarget));
      expect(moreRect.width, greaterThanOrEqualTo(48));
      expect(moreRect.height, greaterThanOrEqualTo(48));
      await tester.tap(find.byKey(const ValueKey('back')));
      await tester.tap(find.byKey(const ValueKey('more')));
      expect([back, more], [1, 1]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('narrow header wraps actions within its content and safe edges', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteFlowPageHeader(
            breadcrumb: 'A long page title',
            onBack: () {},
            actions: [
              for (var i = 0; i < 3; i++)
                IconButton(
                  key: ValueKey('action-$i'),
                  onPressed: () {},
                  icon: const Icon(Icons.more_horiz),
                ),
            ],
          ),
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      final rect = tester.getRect(find.byKey(ValueKey('action-$i')));
      expect(rect.left, greaterThanOrEqualTo(kIsWeb ? 0 : 10));
      expect(rect.right, lessThanOrEqualTo(kIsWeb ? 360 : 350));
      expect(rect.height, greaterThanOrEqualTo(48));
    }
    expect(tester.takeException(), isNull);
  });
}
