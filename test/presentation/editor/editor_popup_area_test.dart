import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/editor/editor_popup_area.dart';

void main() {
  const area = EditorPopupArea(
    origin: Offset(0, 74),
    bounds: Rect.fromLTRB(16, 8, 395, 543),
  );
  test('toolbar subtracts overlay origin and does not cover selected text', () {
    const selection = Rect.fromLTWH(24, 314, 40, 28);
    final local = area.place(selection, const Size(371, 144), centered: true);
    final painted = local.shift(area.origin);
    expect(painted.overlaps(selection), false);
    expect(painted.bottom, selection.top - 8);
    expect(local.intersect(area.bounds), local);
  });
  test('toolbar near top flips below selection within the visible overlay', () {
    const selection = Rect.fromLTWH(24, 80, 40, 28);
    final local = area.place(selection, const Size(371, 144), centered: true);
    expect(local.shift(area.origin).top, selection.bottom + 8);
    expect(local.intersect(area.bounds), local);
  });
  test('slash menu clamps to the actual overlay above the keyboard', () {
    final local = area.place(
      const Rect.fromLTWH(410, 580, 0, 24),
      const Size(320, 320),
      preferBelow: true,
    );
    expect(local.intersect(area.bounds), local);
    expect(local.bottom, lessThanOrEqualTo(543));
  });
  test('short or narrow viewport constrains popup for a scrollable host', () {
    const short = EditorPopupArea(
      origin: Offset(0, 74),
      bounds: Rect.fromLTRB(16, 8, 304, 104),
    );
    final local = short.place(
      const Rect.fromLTWH(24, 100, 20, 20),
      const Size(686, 144),
      centered: true,
    );
    expect(local, short.bounds);
  });
  testWidgets('captures real overlay size beneath development header', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    EditorPopupArea? captured;
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => Column(
          children: [
            const SizedBox(height: 74),
            Expanded(child: child!),
          ],
        ),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(bottom: 24),
              viewInsets: const EdgeInsets.only(bottom: 300),
            ),
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => captured = EditorPopupArea.of(context),
                child: const Text('Measure'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Measure'));
    expect(captured!.origin.dy, 74);
    expect(captured!.bounds.bottom, 504);
    expect(tester.takeException(), null);
  });
}
