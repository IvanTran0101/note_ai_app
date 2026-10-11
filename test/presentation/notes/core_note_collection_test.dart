import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_role.dart';
import 'package:note_ai_app/domain/notes/note_share_grant.dart';
import 'package:note_ai_app/presentation/common/note_flow_primitives.dart';
import 'package:note_ai_app/presentation/notes/animated_note_list.dart';
import 'package:note_ai_app/presentation/notes/notes_theme_tokens.dart';
import 'package:note_ai_app/presentation/notes/notes_list_panel.dart';

void main() {
  final time = DateTime.utc(2026, 10, 1);
  final maskedNote = NoteDto(
    id: 'private',
    ownerId: 'owner',
    title: 'Secret title',
    content: 'Secret body',
    createdAt: time,
    updatedAt: time,
    pinnedAt: time,
    isProtected: true,
    share: NoteShareGrant(
      note: NoteIdentity('owner', 'private'),
      recipientId: 'reader',
      role: NoteRole.viewer,
      sharedAt: time,
      updatedAt: time,
      accessRevision: 1,
      sharerLabel: 'Owner',
    ),
  );
  final note = NoteDto(
    id: 'normal',
    ownerId: 'owner',
    title: 'Weekly plan',
    content: 'Review the notes and prepare the next milestone.',
    createdAt: time,
    updatedAt: time,
  );

  for (final layout in NoteLayoutPreference.values) {
    testWidgets('$layout masks protected text and exposes every status', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedNoteList(
              notes: [maskedNote],
              selectedNoteId: null,
              actionBusy: false,
              layout: layout,
              onSelectNote: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Secret title'), findsNothing);
      expect(find.text('Secret body'), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsWidgets);
      expect(find.byTooltip('Shared note'), findsOneWidget);
      expect(find.byTooltip('Note pinned'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Secret')), findsNothing);
      semantics.dispose();
    });
  }

  for (final width in [320.0, 390.0, 567.0, 768.0, 1280.0]) {
    testWidgets('collection toolbar and cards fit at $width with large text', (
      tester,
    ) async {
      tester.view
        ..physicalSize = Size(width, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: NotesListPanel(
              notes: [note],
              selectedNoteId: null,
              error: null,
              actionBusy: false,
              onNewNote: () {},
              onSelectNote: (_) {},
              onRetry: null,
              queryEnabled: false,
              layout: NoteLayoutPreference.grid,
              onLayoutChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Grid view'), findsOneWidget);
      expect(find.byTooltip('List view'), findsOneWidget);
      expect(find.byKey(const ValueKey('new-note')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('grid is readable at $width with large text', (tester) async {
      tester.view
        ..physicalSize = Size(width, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: AnimatedNoteList(
              notes: [note, maskedNote],
              layout: NoteLayoutPreference.grid,
              selectedNoteId: null,
              actionBusy: false,
              onSelectNote: (_) {},
              canPin: (n) => !n.isProtected,
              onTogglePinned: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Weekly plan'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('pin-normal'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'grid responds to keyboard, pointer, selection, and disabled state',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var selected = false;
      var busy = false;
      var opens = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setter) {
              update = setter;
              return Scaffold(
                body: AnimatedNoteList(
                  notes: [note],
                  layout: NoteLayoutPreference.grid,
                  selectedNoteId: selected ? note.reference : null,
                  actionBusy: busy,
                  onSelectNote: (_) => opens++,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('note-normal'));
      final surface = find.descendant(
        of: card,
        matching: find.byType(AnimatedContainer),
      );
      final tokens = NoteFlowUiTokens.of(tester.element(card));
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: const Offset(790, 590));
      await pointer.moveTo(tester.getCenter(card));
      await tester.pumpAndSettle();
      expect(
        (tester.widget<AnimatedContainer>(surface).decoration! as BoxDecoration)
            .color,
        tokens.subtleSurface,
      );
      await pointer.removePointer();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        (tester.widget<AnimatedContainer>(surface).decoration! as BoxDecoration)
            .border!
            .top
            .color,
        tokens.focusRing,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(opens, 1);
      update(() {
        selected = true;
        busy = true;
      });
      await tester.pumpAndSettle();
      await tester.tap(card);
      expect(opens, 1);
      expect(
        tester.getSemantics(card).flagsCollection.isSelected.toBoolOrNull(),
        isTrue,
      );
      semantics.dispose();
    },
  );

  testWidgets('grid-to-list uses the latest projections, not stale rows', (
    tester,
  ) async {
    var layout = NoteLayoutPreference.grid;
    var notes = [note];
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setter) {
            update = setter;
            return Scaffold(
              body: AnimatedNoteList(
                notes: notes,
                layout: layout,
                selectedNoteId: null,
                actionBusy: false,
                onSelectNote: (_) {},
              ),
            );
          },
        ),
      ),
    );
    update(() => notes = [maskedNote]);
    await tester.pumpAndSettle();
    update(() => layout = NoteLayoutPreference.list);
    await tester.pumpAndSettle();
    expect(find.text('Weekly plan'), findsNothing);
    expect(find.text('Secret title'), findsNothing);
    expect(find.byType(ListTile), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pin toggle semantics do not turn the note-opening action into a switch',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedNoteList(
              notes: [note],
              selectedNoteId: null,
              actionBusy: false,
              layout: NoteLayoutPreference.grid,
              onSelectNote: (_) {},
              canPin: (_) => true,
              onTogglePinned: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('note-normal')))
            .flagsCollection
            .isToggled
            .toBoolOrNull(),
        isNull,
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('pin-normal')))
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isFalse,
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'touch feedback and reduced motion keep cards responsive without replaying entrance',
    (tester) async {
      var opens = 0;
      var notes = [note];
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: StatefulBuilder(
            builder: (context, setter) {
              update = setter;
              return Scaffold(
                body: AnimatedNoteList(
                  notes: notes,
                  selectedNoteId: null,
                  actionBusy: false,
                  onSelectNote: (_) => opens++,
                  layout: NoteLayoutPreference.grid,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('note-normal'));
      final surface = find.descendant(
        of: card,
        matching: find.byType(AnimatedContainer),
      );
      final press = await tester.startGesture(tester.getCenter(card));
      await tester.pump(const Duration(milliseconds: 120));
      expect(opens, 0);
      final container = tester.widget<AnimatedContainer>(surface);
      expect(container.duration, Duration.zero);
      expect(container.transform, Matrix4.identity());
      expect(
        (container.decoration! as BoxDecoration).color,
        NoteFlowUiTokens.light().subtleSurface,
      );
      await press.up();
      await tester.pumpAndSettle();
      expect(opens, 1);
      update(() => notes = [note, maskedNote]);
      await tester.pump();
      expect(
        tester
            .widget<Opacity>(
              find
                  .descendant(
                    of: find.byType(AnimatedNoteList),
                    matching: find.byType(Opacity),
                  )
                  .first,
            )
            .opacity,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion keeps busy status observable without a spinner', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(
          body: NoteFlowPageHeader(
            breadcrumb: 'Notes',
            statusLabel: 'Saving',
            statusBusy: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byTooltip('Saving'), findsOneWidget);
  });
}
