import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_dto.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_localizations.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_recent_rail.dart';

void main() {
  testWidgets(
    'recent cards keep the existing open callback and tap semantics',
    (tester) async {
      final note = _note('A recent note');
      final opened = <NoteDto>[];

      await tester.pumpWidget(
        _app(
          textScale: 1,
          child: Builder(
            builder: (context) => Scaffold(
              body: SizedBox(
                width: 360,
                child: DashboardRecentRail(
                  notes: [note],
                  copy: DashboardCopy.of(context),
                  readable: (_) => true,
                  onOpenNote: opened.add,
                  embeddedInWorkspace: true,
                ),
              ),
            ),
          ),
        ),
      );

      final semantics = tester.ensureSemantics();
      final titleStyle = tester.widget<Text>(find.text('A recent note')).style;
      expect(titleStyle?.fontWeight, FontWeight.w600);
      expect(titleStyle?.color, isNotNull);
      final cardSemantics = tester.getSemantics(find.byType(InkWell));
      expect(
        cardSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );

      await tester.tap(find.byType(InkWell));
      expect(opened, [note]);
      semantics.dispose();
    },
  );

  testWidgets('compact recent title remains inside its card at 200% scale', (
    tester,
  ) async {
    const title =
        'A recent note with a long title that wraps when the text is enlarged';

    await tester.pumpWidget(
      _app(
        textScale: 2,
        child: Builder(
          builder: (context) => Scaffold(
            body: SizedBox(
              width: 360,
              child: DashboardRecentRail(
                notes: [_note(title)],
                copy: DashboardCopy.of(context),
                readable: (_) => true,
                onOpenNote: (_) {},
                embeddedInWorkspace: true,
              ),
            ),
          ),
        ),
      ),
    );

    final cardRect = tester.getRect(find.byType(Card));
    final titleRect = tester.getRect(find.text(title));
    expect(cardRect.height, greaterThan(164));
    expect(titleRect.height, greaterThan(70));
    expect(titleRect.top, greaterThanOrEqualTo(cardRect.top));
    expect(titleRect.bottom, lessThanOrEqualTo(cardRect.bottom));
  });
}

Widget _app({required double textScale, required Widget child}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          size: const Size(360, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: child,
      ),
    ),
  );
}

NoteDto _note(String title) {
  final now = DateTime.utc(2026, 10, 26);
  return NoteDto(
    id: 'recent-note',
    ownerId: 'local-user',
    title: title,
    content: '',
    createdAt: now,
    updatedAt: now,
  );
}
