import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_localizations.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_note_card.dart';
import 'package:note_ai_app/presentation/workspace/workspace_ui_tokens.dart';

void main() {
  testWidgets('compact Home row keeps quiet hierarchy and existing actions', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime.utc(2026, 10, 26);
    final NoteDto note = _note(
      id: 'home',
      title: 'Home focus row',
      content: 'Preview stays hidden in the title-only Home list.',
      now: now,
    );
    NoteDto? opened;
    NoteDto? pinned;

    await _pumpHomeCard(
      tester,
      note: note,
      selected: true,
      onTap: (NoteDto value) => opened = value,
      onTogglePin: (NoteDto value) => pinned = value,
    );

    final Finder card = find.byKey(
      const ValueKey<String>('dashboard-note-card-home'),
    );
    expect(tester.getSize(card).height, greaterThanOrEqualTo(48));
    expect(
      find.text('Preview stays hidden in the title-only Home list.'),
      findsNothing,
    );

    final Card cardWidget = tester.widget<Card>(card);
    final RoundedRectangleBorder cardShape =
        cardWidget.shape! as RoundedRectangleBorder;
    expect(cardShape.borderRadius, BorderRadius.circular(6));

    final Finder inkFinder = find.descendant(
      of: card,
      matching: find.byType(InkWell),
    );
    final InkWell ink = tester.widget<InkWell>(inkFinder.first);
    expect(ink.borderRadius, BorderRadius.circular(6));
    expect(ink.hoverColor, NoteFlowWorkspaceTokens.light().subtleSurface);
    expect(
      ink.focusColor,
      NoteFlowWorkspaceTokens.light().focusRing.withValues(alpha: 0.12),
    );

    final Icon noteIcon = tester.widget<Icon>(
      find.descendant(
        of: card,
        matching: find.byIcon(Icons.description_outlined),
      ),
    );
    expect(noteIcon.size, 16);
    expect(
      noteIcon.color,
      NoteFlowWorkspaceTokens.light().textMuted.withValues(alpha: 0.72),
    );

    final Text title = tester.widget<Text>(
      find.descendant(of: card, matching: find.text(note.title)),
    );
    expect(title.style?.fontSize, 15.5);
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);

    final Semantics semantics = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('dashboard-note-semantics-home')),
    );
    expect(semantics.properties.button, isTrue);
    expect(semantics.properties.selected, isTrue);
    expect(semantics.properties.label, note.title);

    final Finder pin = find.byKey(
      const ValueKey<String>('dashboard-note-pin-home'),
    );
    expect(tester.getSize(pin).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(pin).height, greaterThanOrEqualTo(48));

    await tester.tap(card);
    expect(opened, same(note));
    await tester.tap(pin);
    expect(pinned, same(note));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('narrow compact Home title scales without row overflow', (
    WidgetTester tester,
  ) async {
    final NoteDto note = _note(
      id: 'scaled-home',
      title: 'A deliberately long title remains a single scalable Home row',
      content: 'Existing preview content',
      now: DateTime.utc(2026, 10, 26),
    );
    await _pumpHomeCard(
      tester,
      note: note,
      width: 320,
      height: 640,
      textScale: 1.8,
      onTap: (_) {},
    );

    final Finder card = find.byKey(
      const ValueKey<String>('dashboard-note-card-scaled-home'),
    );
    final Text title = tester.widget<Text>(
      find.descendant(of: card, matching: find.text(note.title)),
    );
    expect(title.style?.fontSize, 16);
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(tester.getSize(card).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}

Future<void> _pumpHomeCard(
  WidgetTester tester, {
  required NoteDto note,
  required ValueChanged<NoteDto> onTap,
  ValueChanged<NoteDto>? onTogglePin,
  bool selected = false,
  double width = 390,
  double height = 844,
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: ThemeData(useMaterial3: true),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        DashboardCopy.delegate,
      ],
      home: Builder(
        builder: (BuildContext context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: DashboardNoteCard(
              key: ValueKey<String>('dashboard-note-${note.id}'),
              note: note,
              copy: DashboardCopy.of(context),
              layout: DashboardNoteCardLayout.list,
              selected: selected,
              showPreview: false,
              compactHomeList: true,
              onTap: onTap,
              onTogglePin: onTogglePin,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

NoteDto _note({
  required String id,
  required String title,
  required String content,
  required DateTime now,
}) => NoteDto(
  id: id,
  ownerId: 'local-user',
  title: title,
  content: content,
  createdAt: now,
  updatedAt: now,
);
