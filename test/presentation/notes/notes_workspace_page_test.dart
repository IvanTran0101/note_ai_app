import 'package:note_ai_app/application/note_intelligence/summary_run_context.dart';
import 'package:note_ai_app/application/note_intelligence/summary_consent_app_service.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/notes/note_security_service.dart';
import 'package:note_ai_app/presentation/notes/note_detail_page.dart';
import 'package:note_ai_app/presentation/notes/notes_workspace_page.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';
import 'package:note_ai_app/presentation/notes/notes_theme_tokens.dart';
import 'package:note_ai_app/presentation/notes/animated_note_list.dart';

final DateTime _baseTime = DateTime.utc(2026, 1, 1);

List<String> _semanticsLabelsWithin(SemanticsNode node) {
  final List<String> labels = <String>[];

  void visit(SemanticsNode current) {
    if (current.label.isNotEmpty) {
      labels.add(current.label);
    }
    current.visitChildren((SemanticsNode child) {
      visit(child);
      return true;
    });
  }

  visit(node);
  return labels;
}

void main() {
  NoteDto buildNote({
    String id = 'note-1',
    String title = 'First note',
    String content = 'First note content',
  }) {
    return NoteDto(
      id: id,
      ownerId: 'local-user',
      title: title,
      content: content,
      createdAt: _baseTime,
      updatedAt: _baseTime,
    );
  }

  Future<void> pumpWorkspace(
    WidgetTester tester,
    _FakeNotesController controller, {
    required Size size,
    bool embeddedInWorkspace = false,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: NotesWorkspacePage(
          controller: controller,
          embeddedInWorkspace: embeddedInWorkspace,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('compact Web page title inset follows measured Notion anchors', () {
    expect(NoteFlowLayout.compactWebPageTopAdjustmentFor(320), 0);
    expect(NoteFlowLayout.compactWebPageTopAdjustmentFor(390), 0);
    expect(
      NoteFlowLayout.compactWebPageTopAdjustmentFor(478.5),
      closeTo(-28, 1),
    );
    expect(NoteFlowLayout.compactWebPageTopAdjustmentFor(567), -56);
    expect(NoteFlowLayout.compactWebPageTopAdjustmentFor(600), 0);
  });

  testWidgets('view preference waits for persistence and restores on remount', (
    tester,
  ) async {
    final controller = _Module02NotesController(notes: [buildNote()])
      ..layout = NoteLayoutPreference.list;
    await pumpWorkspace(tester, controller, size: const Size(1280, 800));
    expect(
      tester.widget<AnimatedNoteList>(find.byType(AnimatedNoteList)).layout,
      NoteLayoutPreference.list,
    );
    controller.layoutGate = Completer<void>();
    await tester.tap(find.byTooltip('Grid view'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('notes-collection-progress')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<SegmentedButton<NoteLayoutPreference>>(
            find.byKey(const ValueKey('notes-layout-control')),
          )
          .onSelectionChanged,
      isNull,
    );
    expect(
      tester.widget<AnimatedNoteList>(find.byType(AnimatedNoteList)).layout,
      NoteLayoutPreference.list,
    );
    controller.layoutGate!.complete();
    await tester.pumpAndSettle();
    expect(controller.layout, NoteLayoutPreference.grid);
    expect(
      tester.widget<AnimatedNoteList>(find.byType(AnimatedNoteList)).layout,
      NoteLayoutPreference.grid,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpWorkspace(tester, controller, size: const Size(1280, 800));
    expect(
      tester.widget<AnimatedNoteList>(find.byType(AnimatedNoteList)).layout,
      NoteLayoutPreference.grid,
    );
    expect(controller.layoutReads, 2);
  });

  testWidgets(
    'failed view write keeps the old layout and offers a real retry',
    (tester) async {
      final controller = _Module02NotesController(notes: [buildNote()])
        ..failLayoutWrite = true;
      await pumpWorkspace(tester, controller, size: const Size(390, 844));
      await tester.tap(find.byTooltip('List view'));
      await tester.pumpAndSettle();
      expect(controller.layout, NoteLayoutPreference.grid);
      expect(
        find.text('Could not save your view preference. Please retry.'),
        findsOneWidget,
      );
      controller.failLayoutWrite = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(controller.layout, NoteLayoutPreference.list);
      expect(
        tester.widget<AnimatedNoteList>(find.byType(AnimatedNoteList)).layout,
        NoteLayoutPreference.list,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed preference load does not hide loaded notes', (
    tester,
  ) async {
    final controller = _Module02NotesController(notes: [buildNote()])
      ..failLayoutRead = true;
    await pumpWorkspace(tester, controller, size: const Size(390, 844));
    expect(find.text('First note'), findsOneWidget);
    expect(find.text('Could not load your view preference.'), findsOneWidget);
    controller
      ..failLayoutRead = false
      ..layout = NoteLayoutPreference.list;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedNoteList>(find.byType(AnimatedNoteList)).layout,
      NoteLayoutPreference.list,
    );
  });

  testWidgets(
    'pin waits for confirmation, reorders, and does not open the editor',
    (tester) async {
      final controller = _Module02NotesController(
        notes: [
          buildNote(id: 'a'),
          buildNote(id: 'b', title: 'Second note'),
        ],
      );
      await pumpWorkspace(tester, controller, size: const Size(1280, 800));
      controller.pinGate = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('pin-b')));
      await tester.pump();
      expect(find.text('Note pinned'), findsNothing);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('pin-b')))
            .onPressed,
        isNull,
      );
      expect(find.byKey(NoteDetailPage.titleFieldKey), findsNothing);
      controller.pinGate!.complete();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedNoteList>(find.byType(AnimatedNoteList))
            .notes
            .first
            .id,
        'b',
      );
      expect(find.text('Note pinned'), findsOneWidget);
      controller.pinGate = null;
      await tester.tap(find.byKey(const ValueKey('pin-b')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedNoteList>(find.byType(AnimatedNoteList))
            .notes
            .first
            .id,
        'a',
      );
      expect(find.text('Note unpinned'), findsOneWidget);
    },
  );

  testWidgets('failed pin keeps its projection and retry uses the controller', (
    tester,
  ) async {
    final controller = _Module02NotesController(notes: [buildNote()])
      ..failPin = true;
    await pumpWorkspace(tester, controller, size: const Size(390, 844));
    await tester.tap(find.byKey(const ValueKey('pin-note-1')));
    await tester.pumpAndSettle();
    expect(controller.notes.single.isPinned, isFalse);
    expect(
      find.text('Could not update the pin. Please retry.'),
      findsOneWidget,
    );
    expect(find.text('Note pinned'), findsNothing);
    controller.failPin = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(controller.notes.single.isPinned, isTrue);
    expect(find.text('Note pinned'), findsOneWidget);
  });

  testWidgets('workspace entry points open notes and drafts inline', (
    WidgetTester tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final _FakeNotesController controller = _FakeNotesController();
    final GlobalKey<NotesWorkspacePageState> pageKey =
        GlobalKey<NotesWorkspacePageState>();
    await tester.pumpWidget(
      MaterialApp(
        home: NotesWorkspacePage(
          key: pageKey,
          controller: controller,
          embeddedInWorkspace: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    pageKey.currentState!.openNote(buildNote());
    await tester.pumpAndSettle();
    expect(find.byKey(NoteDetailPage.titleFieldKey), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(NoteDetailPage.titleFieldKey))
          .controller
          ?.text,
      'First note',
    );

    pageKey.currentState!.startNewNote();
    await tester.pumpAndSettle();
    expect(find.byKey(NoteDetailPage.titleFieldKey), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(NoteDetailPage.titleFieldKey))
          .controller
          ?.text,
      isEmpty,
    );

    await tester.enterText(
      find.byKey(NoteDetailPage.titleFieldKey),
      'Unsaved draft',
    );
    await tester.pump();
    pageKey.currentState!.openNote(
      buildNote(id: 'note-2', title: 'Another note'),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(NoteDetailPage.titleFieldKey))
          .controller
          ?.text,
      'Unsaved draft',
    );
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final int width in <int>[320, 360, 390, 768, 1280]) {
    testWidgets('loading state keeps Notes list structure at ${width}dp', (
      WidgetTester tester,
    ) async {
      tester.view
        ..physicalSize = Size(width.toDouble(), width < 600 ? 568 : 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final _FakeNotesController controller = _FakeNotesController()
        ..listNotesGate = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: NotesWorkspacePage(
            controller: controller,
            embeddedInWorkspace: true,
          ),
        ),
      );
      await tester.pump();

      final Semantics loading = tester.widget<Semantics>(
        find.byKey(const ValueKey<String>('notes-workspace-loading')),
      );
      expect(loading.properties.liveRegion, isTrue);
      expect(loading.properties.label, isNotEmpty);
      expect(
        find.byKey(const ValueKey<String>('notes-workspace-loading-skeleton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('notes-workspace-loading-row-0')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const ValueKey<String>('new-note')), findsNothing);
      expect(find.byKey(const ValueKey<String>('note-note-1')), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.listNotesGate!.complete();
      await tester.pump();
    });
  }

  testWidgets('desktop Notes app bar does not repeat the product name', (
    WidgetTester tester,
  ) async {
    await pumpWorkspace(
      tester,
      _FakeNotesController(),
      size: const Size(1280, 800),
    );

    final AppBar appBar = tester.widget<AppBar>(find.byType(AppBar).first);
    expect(appBar.title, isA<Text>());
    expect((appBar.title! as Text).data, 'Notes');
    expect(find.text('NoteFlow · Notes'), findsNothing);
  });

  for (final int width in <int>[360, 375, 390]) {
    testWidgets('compact list renders without overflow at ${width}dp', (
      WidgetTester tester,
    ) async {
      final _FakeNotesController controller = _FakeNotesController(
        notes: <NoteDto>[
          buildNote(),
          buildNote(
            id: 'note-2',
            title:
                'Second note with a much longer title that must ellipsize '
                'safely on narrow screens',
          ),
        ],
      );
      await pumpWorkspace(
        tester,
        controller,
        size: Size(width.toDouble(), 800),
      );

      expect(find.byKey(const ValueKey<String>('note-note-1')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('note-note-2')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('compact Notes title uses the shared page anchor', (
    WidgetTester tester,
  ) async {
    await pumpWorkspace(
      tester,
      _FakeNotesController(notes: <NoteDto>[buildNote()]),
      size: const Size(390, 844),
      embeddedInWorkspace: true,
    );

    final Finder pageTitle = find.text('Notes').last;
    expect(tester.getTopLeft(pageTitle).dx, 20);
    expect(tester.getTopLeft(pageTitle).dy, NoteFlowSpacing.xl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact Notes keeps New note action beside the title', (
    WidgetTester tester,
  ) async {
    await pumpWorkspace(
      tester,
      _FakeNotesController(notes: <NoteDto>[buildNote()]),
      size: const Size(411, 914),
      embeddedInWorkspace: true,
    );

    final Rect titleRect = tester.getRect(find.text('Notes').last);
    final Rect createRect = tester.getRect(
      find.byKey(const ValueKey<String>('new-note')),
    );
    final Rect firstNoteRect = tester.getRect(
      find.byKey(const ValueKey<String>('note-note-1')),
    );

    expect(createRect.left, greaterThanOrEqualTo(titleRect.right));
    expect(createRect.top, lessThan(titleRect.bottom));
    expect(createRect.bottom, greaterThan(titleRect.top));
    expect(createRect.width, 48);
    expect(find.byTooltip('New note'), findsOneWidget);
    expect(find.text('Every idea, in one calm place.'), findsNothing);
    expect(
      firstNoteRect.top - tester.getRect(find.text('1 note')).bottom,
      lessThanOrEqualTo(NoteFlowSpacing.xxxl),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('security refresh during reload does not leave actions busy', (
    tester,
  ) async {
    final controller = _RefreshingNotesController(notes: [buildNote()]);
    addTearDown(controller.events.close);
    await pumpWorkspace(tester, controller, size: const Size(1024, 700));
    controller.listNotesGate = Completer<void>();
    final reload = tester
        .state<NotesWorkspacePageState>(find.byType(NotesWorkspacePage))
        .reload();
    await tester.pump();
    controller.events.add(null);
    await tester.pump();
    controller.listNotesGate!.complete();
    await reload;
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('notes-collection-progress')),
      findsNothing,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('new-note')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('compact create flow returns to the note list after save', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController();
    await pumpWorkspace(tester, controller, size: const Size(390, 844));

    await tester.tap(find.byKey(const ValueKey<String>('new-note-empty')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('note-detail-title-field')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('note-detail-title-field')),
      'Mobile note',
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('note-detail-content-field')),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('note-detail-content-field')),
      'Created from the compact workspace',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('note-detail-save')),
      findsNothing,
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(controller.notes.single.title, 'Mobile note');
    final VoidCallback? back = tester
        .widget<IconButton>(find.byKey(NoteDetailPage.backKey))
        .onPressed;
    expect(back, isNotNull);
    back!();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('note-note-1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('note-detail-title-field')),
      findsNothing,
    );
  });

  testWidgets(
    'Escape dismisses the more menu without closing the selected editor',
    (tester) async {
      await pumpWorkspace(
        tester,
        _FakeNotesController(notes: [buildNote()]),
        size: const Size(1280, 800),
      );
      await tester.tap(find.byKey(const ValueKey('note-note-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('note-detail-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(NoteDetailPage.moreDeleteKey), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(NoteDetailPage.moreDeleteKey), findsNothing);
      expect(find.byKey(NoteDetailPage.titleFieldKey), findsOneWidget);
    },
  );

  testWidgets('compact detail keeps exactly one titled AppBar', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController(
      notes: <NoteDto>[buildNote()],
    );
    await pumpWorkspace(tester, controller, size: const Size(390, 844));

    expect(find.byType(AppBar), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('note-note-1')));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byKey(NoteDetailPage.backKey), findsOneWidget);
    expect(find.text('First note'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded workspace opens a side peek with a guarded back path', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController(
      notes: <NoteDto>[buildNote()],
    );
    await pumpWorkspace(tester, controller, size: const Size(1024, 700));

    expect(
      find.byKey(const ValueKey<String>('responsive-notes-expanded-surface')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('note-note-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('note-note-1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('note-detail-content-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('responsive-notes-list-pane')),
      findsOneWidget,
    );
    expect(find.byKey(NoteDetailPage.backKey), findsOneWidget);
    await tester.tap(find.byKey(NoteDetailPage.backKey));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('note-note-1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('note-detail-content-field')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide editor back keeps dirty changes behind confirmation', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController(
      notes: <NoteDto>[
        buildNote(),
        buildNote(id: 'note-2', title: 'Second'),
      ],
    );
    await pumpWorkspace(tester, controller, size: const Size(1024, 700));
    await tester.tap(find.byKey(const ValueKey<String>('note-note-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('note-detail-title-field')),
      'Unsaved title',
    );
    await tester.pump();

    await tester.tap(find.byKey(NoteDetailPage.backKey));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('note-detail-back-cancel')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('note-detail-back-cancel')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('note-detail-title-field')),
          )
          .controller!
          .text,
      'Unsaved title',
    );
  });

  testWidgets('reload reads fresh notes for the list', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController(
      notes: <NoteDto>[buildNote()],
    );
    await pumpWorkspace(tester, controller, size: const Size(390, 844));

    expect(find.byKey(const ValueKey<String>('note-note-1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('note-note-2')), findsNothing);
    final int callsBefore = controller.listNotesCalls;

    // The data behind the already-mounted page changes.
    controller.notes.add(buildNote(id: 'note-2', title: 'Second'));

    final NotesWorkspacePageState page = tester.state<NotesWorkspacePageState>(
      find.byType(NotesWorkspacePage),
    );
    await page.reload();
    await tester.pumpAndSettle();

    expect(controller.listNotesCalls, greaterThan(callsBefore));
    expect(find.byKey(const ValueKey<String>('note-note-1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('note-note-2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('load failure is not presented as an empty notes collection', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController()
      ..listNotesError = StateError('offline');
    await pumpWorkspace(tester, controller, size: const Size(1024, 700));

    expect(
      find.byKey(const ValueKey<String>('notes-load-error-state')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('notes-workspace-detail-error')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey<String>('notes-empty')), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('notes-workspace-detail-empty')),
      findsNothing,
    );

    controller.listNotesError = null;
    await tester.tap(find.byKey(const ValueKey<String>('retry-notes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('notes-empty')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('notes-workspace-detail-empty')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('notes load error is announced once in both layouts', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      for (final (Size size, bool embeddedInWorkspace) in <(Size, bool)>[
        (const Size(1024, 700), false),
        (const Size(390, 844), true),
      ]) {
        final _FakeNotesController controller = _FakeNotesController()
          ..listNotesError = StateError('offline');
        await pumpWorkspace(
          tester,
          controller,
          size: size,
          embeddedInWorkspace: embeddedInWorkspace,
        );

        final String error = tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('notes-list-error')),
            )
            .data!;
        final SemanticsNode errorNode = tester.getSemantics(
          find.byKey(const ValueKey<String>('notes-load-error-state')),
        );
        final String accessibleLabels = _semanticsLabelsWithin(errorNode)
            .join('\n');
        expect(
          accessibleLabels.split(error).length - 1,
          1,
          reason: 'Semantics labels: $accessibleLabels',
        );
        expect(
          tester
              .getSemantics(find.byKey(const ValueKey<String>('retry-notes')))
              .flagsCollection
              .isButton,
          isTrue,
        );

        await tester.pumpWidget(const SizedBox.shrink());
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('compact load failure keeps its retry callback', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController()
      ..listNotesError = StateError('offline');
    await pumpWorkspace(
      tester,
      controller,
      size: const Size(390, 844),
      embeddedInWorkspace: true,
    );

    expect(
      find.byKey(const ValueKey<String>('notes-load-error-state')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('retry-notes')), findsOneWidget);
    expect(tester.takeException(), isNull);

    controller.listNotesError = null;
    await tester.tap(find.byKey(const ValueKey<String>('retry-notes')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('notes-empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported note storage has no futile retry action', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController()
      ..listNotesError = UnsupportedError('web storage unavailable');
    await pumpWorkspace(tester, controller, size: const Size(1024, 700));

    expect(
      find.text(
        'This Web build cannot load or save notes. Use the installed app to continue.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('retry-notes')), findsNothing);
    expect(find.byKey(const ValueKey<String>('new-note')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final Size size in <Size>[
    const Size(320, 568),
    const Size(390, 844),
    const Size(567, 694),
  ]) {
    testWidgets('compact storage status stays readable at ${size.width}dp', (
      WidgetTester tester,
    ) async {
      final _FakeNotesController controller = _FakeNotesController()
        ..listNotesError = UnsupportedError('web storage unavailable');
      await pumpWorkspace(
        tester,
        controller,
        size: size,
        embeddedInWorkspace: true,
      );

      final Finder notice = find.byKey(
        const ValueKey<String>('notes-list-error'),
      );
      final Rect noticeBounds = tester.getRect(notice);
      final Rect cardBounds = tester.getRect(
        find.byKey(const ValueKey<String>('notes-load-error-card')),
      );
      final Rect createBounds = tester.getRect(
        find.byKey(const ValueKey<String>('new-note')),
      );
      expect(noticeBounds.left, greaterThanOrEqualTo(0));
      expect(noticeBounds.right, lessThanOrEqualTo(size.width));
      expect(noticeBounds.top, lessThan(createBounds.bottom + 80));
      expect(cardBounds.right, lessThanOrEqualTo(size.width));
      expect(cardBounds.height, lessThan(180));
      expect(
        find.byKey(const ValueKey<String>('notes-load-error-state')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('retry-notes')), findsNothing);
      expect(find.byKey(const ValueKey<String>('new-note')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey<String>('new-note')));
      await tester.pumpAndSettle();
      expect(find.byKey(NoteDetailPage.titleFieldKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('discarding a draft preserves the unsupported storage state', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController()
      ..listNotesError = UnsupportedError('web storage unavailable');
    await pumpWorkspace(tester, controller, size: const Size(1024, 700));

    await tester.tap(find.byKey(const ValueKey<String>('new-note')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('note-detail-title-field')),
      'QA draft',
    );
    await tester.pump();
    await tester.tap(find.byKey(NoteDetailPage.backKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('note-detail-back-discard')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This Web build cannot load or save notes. Use the installed app to continue.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('notes-load-error-state')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('notes-empty')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shares an in-flight reload instead of repeating the request', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController(
      notes: <NoteDto>[buildNote()],
    );
    await pumpWorkspace(tester, controller, size: const Size(390, 844));

    final int callsBefore = controller.listNotesCalls;

    // Hold the next request open so both reloads overlap.
    final Completer<void> gate = Completer<void>();
    controller.listNotesGate = gate;
    controller.notes.add(buildNote(id: 'note-2', title: 'Second'));

    final NotesWorkspacePageState page = tester.state<NotesWorkspacePageState>(
      find.byType(NotesWorkspacePage),
    );
    final Future<void> firstReload = page.reload();
    final Future<void> secondReload = page.reload();
    await tester.pump();

    // The second reload joined the first request instead of issuing its own.
    expect(controller.listNotesCalls, callsBefore + 1);

    gate.complete();
    await tester.pumpAndSettle();
    await firstReload;
    await secondReload;

    // One shared request still delivers the fresh data to both callers.
    expect(controller.listNotesCalls, callsBefore + 1);
    expect(find.byKey(const ValueKey<String>('note-note-2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('center peek backdrop and Escape preserve dirty-close choices', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController(
      notes: <NoteDto>[buildNote()],
    );
    await pumpWorkspace(tester, controller, size: const Size(700, 800));
    await tester.tap(find.byKey(const ValueKey<String>('note-note-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(NoteDetailPage.titleFieldKey),
      'Keep my draft',
    );
    await tester.pump();
    await tester.tapAt(const Offset(8, 100));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('note-detail-back-cancel')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('note-detail-back-cancel')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(NoteDetailPage.titleFieldKey))
          .controller!
          .text,
      'Keep my draft',
    );
    await tester.tap(find.byKey(NoteDetailPage.titleFieldKey));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('note-detail-back-discard')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(NoteDetailPage.titleFieldKey), findsNothing);
    expect(controller.notes.single.title, 'First note');
    expect(tester.takeException(), isNull);
  });
}

class _FakeNotesController implements NotesApplicationController {
  _FakeNotesController({List<NoteDto>? notes})
    : notes = List<NoteDto>.of(notes ?? <NoteDto>[]);

  final List<NoteDto> notes;
  int _nextId = 1;

  /// When set, [listNotes] stays pending until the completer completes so a
  /// test can observe the page while a reload request is in flight.
  Completer<void>? listNotesGate;

  Object? listNotesError;

  /// Number of [listNotes] calls, used to prove reloads are coalesced.
  int listNotesCalls = 0;

  @override
  Future<List<NoteDto>> listNotes() async {
    listNotesCalls++;
    final Completer<void>? gate = listNotesGate;
    if (gate != null) {
      await gate.future;
    }
    if (listNotesError != null) {
      throw listNotesError!;
    }
    return List<NoteDto>.of(notes);
  }

  @override
  Future<NoteDto> createNote({
    required String title,
    required String content,
  }) async {
    final DateTime now = _baseTime.add(const Duration(days: 1));
    final NoteDto note = NoteDto(
      id: 'note-${_nextId++}',
      ownerId: 'local-user',
      title: title,
      content: content,
      createdAt: now,
      updatedAt: now,
    );
    notes.add(note);
    return note;
  }

  @override
  Future<NoteDto> renameNote({
    required String noteId,
    required String title,
  }) async {
    return _replace(_find(noteId), title: title);
  }

  @override
  Future<NoteDto> replaceContent({
    required String noteId,
    required String content,
  }) async {
    return _replace(_find(noteId), content: content);
  }

  @override
  Future<void> deleteNote(String noteId) async {
    notes.removeWhere((NoteDto note) => note.id == noteId);
  }

  @override
  SummaryConsentAppService? get summaryConsent => null;

  @override
  Future<String> summarizeNote(
    String noteId, {
    NoteDto? selectedSnapshot,
    SummaryRunScope? scope,
  }) async => 'Summary of ${_find(noteId).content}';

  NoteDto _find(String id) => notes.firstWhere((NoteDto note) => note.id == id);

  NoteDto _replace(NoteDto current, {String? title, String? content}) {
    final NoteDto updated = NoteDto(
      id: current.id,
      ownerId: current.ownerId,
      title: title ?? current.title,
      content: content ?? current.content,
      createdAt: current.createdAt,
      updatedAt: current.updatedAt.add(const Duration(minutes: 1)),
    );
    notes[notes.indexOf(current)] = updated;
    return updated;
  }
}

class _Module02NotesController extends _FakeNotesController
    implements NotesModule02Controller {
  _Module02NotesController({super.notes});
  NoteLayoutPreference layout = NoteLayoutPreference.grid;
  int layoutReads = 0;
  bool failLayoutRead = false;
  bool failLayoutWrite = false;
  bool failPin = false;
  Completer<void>? layoutGate;
  Completer<void>? pinGate;
  @override
  Future<NoteLayoutPreference> getNoteLayout() async {
    layoutReads++;
    if (failLayoutRead) throw StateError('preference unavailable');
    return layout;
  }

  @override
  Future<void> setNoteLayout(NoteLayoutPreference value) async {
    await layoutGate?.future;
    if (failLayoutWrite) throw StateError('write failed');
    layout = value;
  }

  @override
  Future<NoteDto> setPinned({
    required String noteId,
    required bool pinned,
  }) async {
    await pinGate?.future;
    if (failPin) throw StateError('pin failed');
    final current = _find(noteId);
    final saved = NoteDto(
      id: current.id,
      ownerId: current.ownerId,
      title: current.title,
      content: current.content,
      createdAt: current.createdAt,
      updatedAt: current.updatedAt,
      pinnedAt: pinned ? _baseTime : null,
    );
    notes[notes.indexOf(current)] = saved;
    return saved;
  }

  @override
  Future<NoteDto> updateNote({
    required String noteId,
    required String title,
    required String content,
  }) async {
    await renameNote(noteId: noteId, title: title);
    return replaceContent(noteId: noteId, content: content);
  }
}

final class _RefreshingNotesController extends _Module02NotesController
    implements SecuredNotesController {
  _RefreshingNotesController({required super.notes});
  final events = StreamController<void>.broadcast();
  @override
  Stream<void> get securityChanges => events.stream;
  @override
  int get accessGeneration => 0;
  @override
  int get sessionGeneration => 0;
  @override
  bool get securityServerAvailable => false;
  @override
  NoteSecurityService? get noteSecurity => null;
  @override
  Future<NoteDto> readNote(String id) async =>
      notes.firstWhere((note) => note.reference == id);
  @override
  NoteAccessCapabilities capabilitiesFor(NoteDto note) =>
      const NoteAccessCapabilities(
        canRead: true,
        canEdit: true,
        canDelete: true,
        canManage: true,
      );
}
