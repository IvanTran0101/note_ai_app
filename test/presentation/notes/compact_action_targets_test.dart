import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/presentation/common/note_flow_primitives.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_localizations.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_note_card.dart';
import 'package:note_ai_app/presentation/notes/note_detail_localizations.dart';
import 'package:note_ai_app/presentation/notes/note_detail_summary.dart';

void main() {
  Future<void> pump(WidgetTester tester, WidgetBuilder builder) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [DashboardCopy.delegate],
        home: Scaffold(body: Builder(builder: builder)),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final layout in DashboardNoteCardLayout.values) {
    testWidgets('compact Home pin has48 target in $layout', (tester) async {
      var pins = 0;
      final time = DateTime.utc(2026);
      final note = NoteDto(
        id: 'touch-target',
        ownerId: 'qa-owner',
        title: 'Touch target',
        content: 'Local content',
        createdAt: time,
        updatedAt: time,
      );
      await pump(
        tester,
        (context) => SizedBox(
          width: 350,
          height: 180,
          child: DashboardNoteCard(
            note: note,
            onTap: (_) {},
            onTogglePin: (_) => pins++,
            copy: DashboardCopy.of(context),
            layout: layout,
          ),
        ),
      );
      final pin = find.byTooltip('Pin note');
      expect(tester.getSize(pin).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(pin).height, greaterThanOrEqualTo(48));
      await tester.tapAt(tester.getBottomRight(pin) - const Offset(1, 1));
      expect(pins, 1);
    });
  }

  testWidgets('compact summary collapse has48 target', (tester) async {
    await pump(
      tester,
      (context) => NoteDetailSummary(
        copy: NoteDetailCopy.of(context),
        hasSavedNote: true,
        summary: 'Existing summary',
        isStale: false,
      ),
    );
    final toggle = find.byKey(const ValueKey('note-detail-summary-toggle'));
    expect(tester.getSize(toggle).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
    await tester.tapAt(tester.getBottomRight(toggle) - const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(tester.widget(toggle), isA<OutlinedButton>());
  });

  for (final dense in [false, true]) {
    testWidgets('compact sidebar dense=$dense has48 ink target', (
      tester,
    ) async {
      var calls = 0;
      await pump(
        tester,
        (_) => NoteFlowSidebarRow(
          label: 'Settings',
          icon: Icons.settings_outlined,
          dense: dense,
          onTap: () => calls++,
        ),
      );
      final ink = find.byType(InkWell);
      expect(tester.getSize(ink).height, greaterThanOrEqualTo(48));
      await tester.tapAt(
        Offset(tester.getCenter(ink).dx, tester.getBottomLeft(ink).dy - 1),
      );
      expect(calls, 1);
    });
  }
}
