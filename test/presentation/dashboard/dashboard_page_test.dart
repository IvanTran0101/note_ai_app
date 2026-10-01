import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/note_intelligence/summary_consent_app_service.dart';

import 'package:note_ai_app/application/dashboard/dashboard_overview.dart';
import 'package:note_ai_app/application/dashboard/get_dashboard_overview.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/note_intelligence/summary_run_context.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_controller.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_localizations.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_note_card.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_page.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_state.dart';
import 'package:note_ai_app/presentation/notes/note_detail_route_result.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';
import 'package:note_ai_app/presentation/notes/notes_theme_tokens.dart';
import 'package:note_ai_app/presentation/workspace/workspace_localizations.dart';
import 'package:note_ai_app/presentation/workspace/workspace_shell.dart';
import 'package:note_ai_app/presentation/workspace/workspace_ui_tokens.dart';

final DateTime _baseTime = DateTime.utc(2026, 9, 10, 9);

void main() {
  group('DashboardCopy', () {
    test('delegate supports English and Vietnamese only', () {
      expect(DashboardCopy.delegate.isSupported(const Locale('en')), isTrue);
      expect(DashboardCopy.delegate.isSupported(const Locale('vi')), isTrue);
      expect(DashboardCopy.delegate.isSupported(const Locale('fr')), isFalse);
    });

    test('loads localized labels for each supported locale', () async {
      final DashboardCopy english = await DashboardCopy.delegate.load(
        const Locale('en'),
      );
      final DashboardCopy vietnamese = await DashboardCopy.delegate.load(
        const Locale('vi'),
      );

      expect(english.title, 'Home');
      expect(vietnamese.title, 'Trang chủ');
      expect(english.workspaceLabel, 'NoteFlow');
      expect(english.noteCount(1), '1 note');
      expect(english.noteCount(3), '3 notes');
      expect(vietnamese.noteCount(3), '3 ghi chú');
    });
  });

  group('DashboardPage', () {
    testWidgets('shows a loading skeleton while the overview is pending', (
      WidgetTester tester,
    ) async {
      final Completer<DashboardOverview> completer =
          Completer<DashboardOverview>();
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery.pending(completer),
      );

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: _FakeNotesController(notes: <NoteDto>[_buildNote()]),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('dashboard-loading')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('dashboard-content')),
        findsNothing,
      );

      completer.complete(_overview(notes: <NoteDto>[_buildNote()]));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('dashboard-loading')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('dashboard-content')),
        findsOneWidget,
      );
    });

    testWidgets('renders the note collection and toggles grid and list', (
      WidgetTester tester,
    ) async {
      final List<NoteDto> notes = <NoteDto>[
        _buildNote(id: 'a', title: 'Alpha', content: 'Alpha body'),
        _buildNote(id: 'b', title: 'Beta', content: 'Beta body'),
      ];
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery(_overview(notes: notes)),
      );

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: _FakeNotesController(notes: notes),
        size: const Size(1440, 900),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DashboardNoteCard), findsNWidgets(2));
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('2 notes'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('dashboard-total-count')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('dashboard-last-updated')),
        findsOneWidget,
      );
      expect(_cardFor(tester, 'a').layout, DashboardNoteCardLayout.grid);
      final Card firstCard = tester.widget<Card>(
        find.byKey(const ValueKey<String>('dashboard-note-card-a')),
      );
      expect(firstCard.elevation, 0);
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey<String>('dashboard-note-card-a')),
            )
            .height,
        greaterThanOrEqualTo(56),
      );

      await tester.tap(find.byIcon(Icons.view_list_outlined));
      await tester.pumpAndSettle();

      expect(_cardFor(tester, 'a').layout, DashboardNoteCardLayout.list);
      expect(_cardFor(tester, 'b').layout, DashboardNoteCardLayout.list);

      await tester.tap(find.byIcon(Icons.grid_view_outlined));
      await tester.pumpAndSettle();

      expect(_cardFor(tester, 'a').layout, DashboardNoteCardLayout.grid);
      expect(_cardFor(tester, 'b').layout, DashboardNoteCardLayout.grid);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('dashboard-note-card-a')),
          matching: find.byIcon(Icons.description_outlined),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byIcon(Icons.view_list_outlined));
      await tester.pumpAndSettle();

      expect(_cardFor(tester, 'a').layout, DashboardNoteCardLayout.list);
      expect(_cardFor(tester, 'b').layout, DashboardNoteCardLayout.list);
    });

    testWidgets('wide Home matches the Notion page column and title anchor', (
      WidgetTester tester,
    ) async {
      final List<NoteDto> notes = <NoteDto>[_buildNote(id: 'a')];
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery(_overview(notes: notes)),
      );

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: _FakeNotesController(notes: notes),
        size: const Size(1440, 900),
        embeddedInWorkspace: true,
      );
      await tester.pumpAndSettle();

      final AppBar appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.toolbarHeight, 44);
      expect(find.text('NoteFlow / Home'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);

      final Finder pageColumn = find.byWidgetPredicate(
        (Widget widget) =>
            widget is ConstrainedBox &&
            widget.constraints.maxWidth ==
                NoteFlowLayout.dashboardContentMaxWidth,
      );
      expect(pageColumn, findsOneWidget);
      expect(tester.getSize(pageColumn).width, 768);
      expect(tester.getTopLeft(find.text('Home')).dx, closeTo(360, 4));
      expect(tester.getTopLeft(find.text('Home')).dy, closeTo(120, 4));
      expect(tester.takeException(), isNull);
    });

    testWidgets('compact Home starts with the Notion-style Recents section', (
      WidgetTester tester,
    ) async {
      final List<NoteDto> notes = <NoteDto>[_buildNote(id: 'a')];
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery(_overview(notes: notes)),
      );

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: _FakeNotesController(notes: notes),
        size: const Size(390, 844),
        embeddedInWorkspace: true,
      );
      await tester.pumpAndSettle();

      final Finder pageColumn = find.byWidgetPredicate(
        (Widget widget) =>
            widget is ConstrainedBox &&
            widget.constraints.maxWidth ==
                NoteFlowLayout.compactPageFrameMaxWidthFor(
                  tester.element(find.byType(DashboardPage)),
                ),
      );
      expect(pageColumn, findsOneWidget);
      expect(tester.getSize(pageColumn).width, 390);
      // The compact page starts with the section title at the phone edge.
      expect(find.text('Home'), findsNothing);
      expect(find.text('Recents'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Recents')).dx, closeTo(24, 1));
      expect(tester.getTopLeft(find.text('Recents')).dy, closeTo(20, 1));
      final Text recentHeading = tester.widget<Text>(find.text('Recents'));
      expect(
        recentHeading.style?.color,
        NoteFlowWorkspaceTokens.light().textSecondary,
      );
      expect(recentHeading.style?.fontWeight, FontWeight.w500);
      final Finder recentCard = find.byType(Card).first;
      expect(tester.getSize(recentCard).width, closeTo(132, 0.1));
      expect(tester.getSize(recentCard).height, closeTo(132, 0.1));
      expect(find.text('First note body.'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('compact Home keeps Recents clear of its shell actions', (
      WidgetTester tester,
    ) async {
      const Size viewport = Size(390, 844);
      tester.view
        ..physicalSize = viewport
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final List<NoteDto> notes = <NoteDto>[_buildNote(id: 'a')];
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery(_overview(notes: notes)),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('vi'),
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            DashboardCopy.delegate,
            WorkspaceCopy.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
          home: MediaQuery(
            data: const MediaQueryData(
              size: viewport,
              devicePixelRatio: 1,
              padding: EdgeInsets.only(top: 24),
              viewPadding: EdgeInsets.only(top: 24),
            ),
            child: WorkspaceShell(
              dashboard: DashboardPage(
                dashboardController: controller,
                notesController: _FakeNotesController(notes: notes),
                onOpenNote: (NoteDto _) => null,
                onCreateNote: () => null,
                embeddedInWorkspace: true,
              ),
              notes: const SizedBox.shrink(),
              onOpenSearch: () {},
              onCreateNote: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Gần đây'), findsOneWidget);
      final Rect heading = tester.getRect(find.text('Gần đây'));
      expect(heading.top, greaterThanOrEqualTo(24));
      expect(heading.top, lessThan(120));
      final Rect bottomActions = tester.getRect(
        find.byKey(WorkspaceShell.compactBottomNavigationKey),
      );
      expect(heading.bottom, lessThan(bottomActions.top));
      expect(find.byKey(WorkspaceShell.compactSearchKey), findsOneWidget);
      expect(find.byKey(WorkspaceShell.compactFabNewNoteKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final Size viewport in <Size>[
      const Size(360, 800),
      const Size(375, 667),
      const Size(393, 852),
      const Size(412, 915),
      const Size(600, 900),
      const Size(768, 1024),
      const Size(839, 1024),
      const Size(840, 900),
      const Size(1024, 1366),
      const Size(1280, 800),
      const Size(1440, 900),
    ]) {
      testWidgets('keeps Home usable at ${viewport.width}dp', (
        WidgetTester tester,
      ) async {
        final List<NoteDto> notes = <NoteDto>[_buildNote(id: 'a')];
        final DashboardController controller = DashboardController(
          query: _FakeDashboardQuery(_overview(notes: notes)),
        );

        await _pumpDashboard(
          tester,
          dashboardController: controller,
          notesController: _FakeNotesController(notes: notes),
          size: viewport,
        );
        await tester.pumpAndSettle();

        expect(find.byKey(DashboardPage.contentKey), findsOneWidget);
        expect(find.byKey(DashboardPage.newNoteKey), findsOneWidget);
        expect(
          _cardFor(tester, 'a').layout,
          viewport.width >= 840
              ? DashboardNoteCardLayout.grid
              : DashboardNoteCardLayout.list,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('wide Home uses four cards across its centered page column', (
      WidgetTester tester,
    ) async {
      final List<NoteDto> notes = <NoteDto>[
        for (int index = 0; index < 7; index++)
          _buildNote(id: 'note-$index', title: 'Note $index'),
      ];
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery(_overview(notes: notes)),
      );

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: _FakeNotesController(notes: notes),
        size: const Size(1440, 900),
      );
      await tester.pumpAndSettle();

      final double firstRowY = tester
          .getTopLeft(
            find.byKey(const ValueKey<String>('dashboard-note-note-0')),
          )
          .dy;
      for (int index = 1; index < 4; index++) {
        final Finder card = find.byKey(
          ValueKey<String>('dashboard-note-note-$index'),
        );
        expect(tester.getTopLeft(card).dy, closeTo(firstRowY, 0.5));
        expect(tester.getSize(card).width, greaterThanOrEqualTo(136));
      }
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey<String>('dashboard-note-note-4')),
            )
            .dy,
        greaterThan(firstRowY),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide Home grid survives 200 percent text scaling', (
      WidgetTester tester,
    ) async {
      final List<NoteDto> notes = <NoteDto>[
        _buildNote(
          id: 'long',
          title: 'A long page title that should wrap and truncate safely',
          content:
              'A long note preview that should remain inside the compact grid '
              'card at large text sizes.',
        ),
      ];
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery(_overview(notes: notes)),
      );

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: _FakeNotesController(notes: notes),
        size: const Size(1440, 900),
        textScale: 2.0,
      );
      await tester.pumpAndSettle();

      expect(_cardFor(tester, 'long').layout, DashboardNoteCardLayout.grid);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Grid and List use distinct compact layouts', (
      WidgetTester tester,
    ) async {
      final List<NoteDto> notes = <NoteDto>[
        _buildNote(id: 'a'),
        _buildNote(id: 'b'),
      ];
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery(_overview(notes: notes)),
      );

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: _FakeNotesController(notes: notes),
        size: const Size(400, 900),
      );
      await tester.pumpAndSettle();

      final double listA = tester
          .getTopLeft(find.byKey(const ValueKey<String>('dashboard-note-a')))
          .dy;
      final double listB = tester
          .getTopLeft(find.byKey(const ValueKey<String>('dashboard-note-b')))
          .dy;
      expect(listA, isNot(listB));

      await tester.tap(find.byIcon(Icons.grid_view_outlined));
      await tester.pumpAndSettle();

      final double compactA = tester
          .getTopLeft(find.byKey(const ValueKey<String>('dashboard-note-a')))
          .dy;
      final double compactB = tester
          .getTopLeft(find.byKey(const ValueKey<String>('dashboard-note-b')))
          .dy;
      expect(compactA, compactB);

      await tester.tap(find.byIcon(Icons.view_list_outlined));
      await tester.pumpAndSettle();

      final double listAfterToggleA = tester
          .getTopLeft(find.byKey(const ValueKey<String>('dashboard-note-a')))
          .dy;
      final double listAfterToggleB = tester
          .getTopLeft(find.byKey(const ValueKey<String>('dashboard-note-b')))
          .dy;
      expect(listAfterToggleA, isNot(listAfterToggleB));

      await tester.tap(find.byIcon(Icons.grid_view_outlined));
      await tester.pumpAndSettle();

      tester.view.physicalSize = const Size(1200, 900);
      await tester.pumpAndSettle();

      final double wideA = tester
          .getTopLeft(find.byKey(const ValueKey<String>('dashboard-note-a')))
          .dy;
      final double wideB = tester
          .getTopLeft(find.byKey(const ValueKey<String>('dashboard-note-b')))
          .dy;
      expect(wideA, wideB);
    });

    for (final int width in <int>[320, 360, 390]) {
      testWidgets('Vietnamese header fits at ${width}dp', (
        WidgetTester tester,
      ) async {
        final List<NoteDto> notes = <NoteDto>[_buildNote(id: 'a')];
        final DashboardController controller = DashboardController(
          query: _FakeDashboardQuery(_overview(notes: notes)),
        );

        await _pumpDashboard(
          tester,
          dashboardController: controller,
          notesController: _FakeNotesController(notes: notes),
          locale: const Locale('vi'),
          size: Size(width.toDouble(), 568),
        );
        await tester.pumpAndSettle();

        expect(find.text('Trang chủ'), findsOneWidget);
        expect(
          tester
              .getSize(
                find.byKey(const ValueKey<String>('dashboard-create-note')),
              )
              .height,
          greaterThanOrEqualTo(48),
        );
        expect(tester.takeException(), isNull);
      });
    }

    for (final double textScale in <double>[1.5, 2.0]) {
      testWidgets(
        'Dashboard survives ${textScale}x text scale on compact width',
        (WidgetTester tester) async {
          final List<NoteDto> notes = <NoteDto>[_buildNote(id: 'a')];
          final DashboardController controller = DashboardController(
            query: _FakeDashboardQuery(_overview(notes: notes)),
          );

          await _pumpDashboard(
            tester,
            dashboardController: controller,
            notesController: _FakeNotesController(notes: notes),
            size: const Size(320, 900),
            textScale: textScale,
          );
          await tester.pumpAndSettle();

          expect(find.byKey(DashboardPage.contentKey), findsOneWidget);
          expect(find.byType(DashboardNoteCard), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('shows the empty state and creates the first note', (
      WidgetTester tester,
    ) async {
      bool created = false;
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery(_overview(notes: const <NoteDto>[])),
      );

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: _FakeNotesController(),
        onCreateNote: () => created = true,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('dashboard-empty')),
        findsOneWidget,
      );
      expect(find.text('No notes yet'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('dashboard-create-note')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('dashboard-empty-create')),
      );
      expect(created, isTrue);
    });

    testWidgets('shows filtered-empty and recovers when search is cleared', (
      WidgetTester tester,
    ) async {
      final List<NoteDto> notes = <NoteDto>[
        _buildNote(id: 'a', title: 'Alpha', content: 'Alpha body'),
      ];
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery(_overview(notes: notes)),
      );

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: _FakeNotesController(notes: notes),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('dashboard-search-toggle')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('dashboard-search-field')),
        'zzz',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('dashboard-filtered-empty')),
        findsOneWidget,
      );
      expect(find.byType(DashboardNoteCard), findsNothing);
      expect(find.text('No matching notes'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('dashboard-clear-search-action')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DashboardNoteCard), findsOneWidget);
    });

    testWidgets('compact Search matches the page hierarchy and can close', (
      WidgetTester tester,
    ) async {
      final List<bool> searchVisibilityChanges = <bool>[];
      final List<NoteDto> notes = <NoteDto>[
        _buildNote(
          id: 'a',
          title: 'Alpha',
          content: 'Alpha body',
          updatedAt: DateTime.now(),
        ),
      ];
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery(_overview(notes: notes)),
      );

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: _FakeNotesController(notes: notes),
        size: const Size(390, 844),
        onSearchVisibilityChanged: searchVisibilityChanges.add,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('dashboard-search-toggle')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('dashboard-search-field')),
        'Alpha',
      );
      await tester.pumpAndSettle();

      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Results'), findsOneWidget);
      expect(find.text('Today'), findsNothing);
      expect(find.text('Recents'), findsNothing);
      expect(find.text('All notes'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('dashboard-layout-toggle')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('dashboard-search-sort')),
        findsOneWidget,
      );
      expect(find.text('Alpha'), findsWidgets);
      expect(searchVisibilityChanges, <bool>[true]);
      expect(
        find.byKey(const ValueKey<String>('dashboard-search-close')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('dashboard-search-close')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('dashboard-search-field')),
        findsNothing,
      );
      expect(searchVisibilityChanges, <bool>[true, false]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('workspace Search docks the existing query and sort actions', (
      WidgetTester tester,
    ) async {
      final List<bool> searchVisibilityChanges = <bool>[];
      final List<NoteDto> notes = <NoteDto>[
        _buildNote(id: 'a', title: 'Alpha', content: 'Alpha body'),
      ];
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery(_overview(notes: notes)),
      );

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: _FakeNotesController(notes: notes),
        embeddedInWorkspace: true,
        size: const Size(390, 844),
        onSearchVisibilityChanged: searchVisibilityChanges.add,
      );
      await tester.pumpAndSettle();

      tester.state<DashboardPageState>(find.byType(DashboardPage)).openSearch();
      await tester.pumpAndSettle();
      expect(find.byKey(DashboardPage.searchDockKey), findsOneWidget);
      expect(find.byKey(DashboardPage.searchFieldKey), findsOneWidget);
      expect(find.byKey(DashboardPage.searchDockSortKey), findsOneWidget);
      expect(find.byKey(DashboardPage.searchDockCloseKey), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('dashboard-search-close')),
        findsNothing,
      );
      expect(find.text('Recents'), findsNothing);
      expect(find.text('All notes'), findsNothing);

      await tester.enterText(find.byKey(DashboardPage.searchFieldKey), 'Alpha');
      await tester.pumpAndSettle();
      expect(find.text('Results'), findsOneWidget);
      expect(find.text('Alpha'), findsWidgets);
      expect(find.byKey(DashboardPage.searchDockSortKey), findsOneWidget);

      await tester.tap(find.byKey(DashboardPage.searchDockCloseKey));
      await tester.pumpAndSettle();
      expect(find.byKey(DashboardPage.searchDockKey), findsNothing);
      expect(searchVisibilityChanges, <bool>[true, false]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('workspace desktop Search opens a dismissible overlay', (
      WidgetTester tester,
    ) async {
      final List<bool> searchVisibilityChanges = <bool>[];
      final List<NoteDto> notes = <NoteDto>[
        _buildNote(
          id: 'a',
          title: 'Alpha',
          content: 'Alpha body',
          updatedAt: DateTime.now(),
        ),
      ];
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery(_overview(notes: notes)),
      );

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: _FakeNotesController(notes: notes),
        embeddedInWorkspace: true,
        size: const Size(1200, 900),
        onSearchVisibilityChanged: searchVisibilityChanges.add,
      );
      await tester.pumpAndSettle();

      tester.state<DashboardPageState>(find.byType(DashboardPage)).openSearch();
      await tester.pumpAndSettle();
      expect(find.byKey(DashboardPage.desktopSearchOverlayKey), findsOneWidget);
      expect(find.byKey(DashboardPage.searchFieldKey), findsOneWidget);
      expect(find.text('Search'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('dashboard-search-close')),
        findsOneWidget,
      );
      expect(
        find.byKey(DashboardPage.layoutToggleKey).hitTestable(),
        findsNothing,
      );
      final Finder desktopSearchOverlay = find.byKey(
        DashboardPage.desktopSearchOverlayKey,
      );
      final Rect desktopSearchRect = tester.getRect(
        find.byKey(DashboardPage.desktopSearchSurfaceKey),
      );
      expect(desktopSearchRect.width, closeTo(1008, 1));
      expect(desktopSearchRect.height, closeTo(704, 1));
      expect(desktopSearchRect.top, closeTo(65, 1));
      expect(
        find.descendant(
          of: desktopSearchOverlay,
          matching: find.text('Recents'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: desktopSearchOverlay,
          matching: find.text('All notes'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: desktopSearchOverlay,
          matching: find.text('Results'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: desktopSearchOverlay, matching: find.text('Today')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: desktopSearchOverlay,
          matching: find.byType(DashboardNoteCard),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: desktopSearchOverlay, matching: find.text('Alpha')),
        findsOneWidget,
      );

      await tester.enterText(find.byKey(DashboardPage.searchFieldKey), 'Alpha');
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: desktopSearchOverlay,
          matching: find.text('Alpha body'),
        ),
        findsOneWidget,
      );
      expect(
        find.byType(PopupMenuButton<DashboardSort>).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(DashboardPage.layoutToggleKey).hitTestable(),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('dashboard-search-close')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(DashboardPage.desktopSearchOverlayKey), findsNothing);
      expect(find.byKey(DashboardPage.searchFieldKey), findsNothing);
      expect(searchVisibilityChanges, <bool>[true, false]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a friendly error and retries without raw text', (
      WidgetTester tester,
    ) async {
      final List<NoteDto> notes = <NoteDto>[_buildNote(id: 'a')];
      final _FakeDashboardQuery query = _FakeDashboardQuery(
        _overview(notes: notes),
      )..error = StateError('storage exploded');
      final DashboardController controller = DashboardController(query: query);

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: _FakeNotesController(notes: notes),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('dashboard-error')),
        findsOneWidget,
      );
      expect(find.textContaining('storage exploded'), findsNothing);
      expect(
        find.text('Couldn’t load notes. Please try again.'),
        findsOneWidget,
      );

      query.error = null;
      await tester.tap(find.byKey(const ValueKey<String>('dashboard-retry')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('dashboard-error')),
        findsNothing,
      );
      expect(find.byType(DashboardNoteCard), findsOneWidget);
      expect(query.calls, greaterThanOrEqualTo(2));
    });

    testWidgets('surfaces a note-list failure with a retry action', (
      WidgetTester tester,
    ) async {
      final List<NoteDto> notes = <NoteDto>[_buildNote(id: 'a')];
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery(_overview(notes: notes)),
      );

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: _FakeNotesController(
          notes: notes,
          listNotesError: StateError('disk unavailable'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('dashboard-notes-error')),
        findsOneWidget,
      );
      expect(find.textContaining('disk unavailable'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('dashboard-notes-retry')),
        findsOneWidget,
      );
    });

    testWidgets('explains unsupported note storage without a retry action', (
      WidgetTester tester,
    ) async {
      final List<NoteDto> notes = <NoteDto>[_buildNote(id: 'a')];
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery(_overview(notes: notes)),
      );

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: _FakeNotesController(
          notes: notes,
          listNotesError: UnsupportedError('web storage unavailable'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This Web build cannot load or save notes. Use the installed app to continue.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('dashboard-notes-retry')),
        findsNothing,
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.cloud_off_outlined)).color,
        NoteFlowWorkspaceTokens.light().textMuted,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens a note and marks its card selected when tapped', (
      WidgetTester tester,
    ) async {
      final List<NoteDto> notes = <NoteDto>[
        _buildNote(id: 'a', title: 'Alpha', content: 'Alpha body'),
      ];
      NoteDto? opened;
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery(_overview(notes: notes)),
      );

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: _FakeNotesController(notes: notes),
        onOpenNote: (NoteDto note) => opened = note,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('dashboard-note-a')));
      await tester.pumpAndSettle();

      expect(opened?.id, 'a');
      expect(_cardFor(tester, 'a').selected, isTrue);
    });

    testWidgets('selected card uses selected contrast and semantics', (
      WidgetTester tester,
    ) async {
      final List<NoteDto> notes = <NoteDto>[
        _buildNote(id: 'a', title: 'Alpha', content: 'Alpha body'),
      ];
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery(_overview(notes: notes)),
      );

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: _FakeNotesController(notes: notes),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('dashboard-note-a')));
      await tester.pump();

      final Finder cardFinder = find.byKey(
        const ValueKey<String>('dashboard-note-card-a'),
      );
      final Text title = tester.widget<Text>(
        find.descendant(of: cardFinder, matching: find.text('Alpha')),
      );
      final Card card = tester.widget<Card>(cardFinder);
      final NoteFlowWorkspaceTokens tokens = NoteFlowWorkspaceTokens.of(
        tester.element(find.byType(DashboardPage)),
      );
      expect(card.color, tokens.selectedSurface);
      expect(title.style?.color, tokens.textPrimary);

      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey<String>('dashboard-note-semantics-a')),
            )
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isTrue,
      );
    });

    testWidgets('reloads projections only when a detail result requests it', (
      WidgetTester tester,
    ) async {
      final NoteDto original = _buildNote(id: 'a', title: 'Alpha');
      final NoteDto updated = _buildNote(id: 'a', title: 'Renamed');
      final _FakeNotesController notesController = _FakeNotesController(
        notes: <NoteDto>[original],
      );
      final _FakeDashboardQuery query = _FakeDashboardQuery(
        _overview(notes: <NoteDto>[original]),
      );
      final DashboardController controller = DashboardController(query: query);

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: notesController,
        onOpenNoteResult: (NoteDto note) {
          notesController.notes[0] = updated;
          query.result = _overview(notes: <NoteDto>[updated]);
          return NoteDetailRouteResult(
            reason: NoteDetailExitReason.saved,
            note: updated,
          );
        },
      );
      await tester.pumpAndSettle();
      final int callsBeforeTap = query.calls;

      await tester.tap(find.byKey(const ValueKey<String>('dashboard-note-a')));
      await tester.pumpAndSettle();

      expect(query.calls, greaterThan(callsBeforeTap));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('dashboard-note-a')),
          matching: find.text('Renamed'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('invokes create from the loaded state action', (
      WidgetTester tester,
    ) async {
      final List<NoteDto> notes = <NoteDto>[_buildNote(id: 'a')];
      bool created = false;
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery(_overview(notes: notes)),
      );

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: _FakeNotesController(notes: notes),
        onCreateNote: () => created = true,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('dashboard-create-note')),
      );
      expect(created, isTrue);
    });

    testWidgets('invokes optional settings and diagnostics callbacks', (
      WidgetTester tester,
    ) async {
      final List<NoteDto> notes = <NoteDto>[_buildNote(id: 'a')];
      bool settings = false;
      bool diagnostics = false;
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery(_overview(notes: notes)),
      );

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: _FakeNotesController(notes: notes),
        onOpenSettings: () => settings = true,
        onOpenDiagnostics: () => diagnostics = true,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('dashboard-open-settings')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('dashboard-open-diagnostics')),
      );

      expect(settings, isTrue);
      expect(diagnostics, isTrue);
    });

    testWidgets('renders English labels by default', (
      WidgetTester tester,
    ) async {
      final List<NoteDto> notes = <NoteDto>[_buildNote(id: 'a')];
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery(_overview(notes: notes)),
      );

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: _FakeNotesController(notes: notes),
        locale: const Locale('en'),
      );
      await tester.pumpAndSettle();

      expect(find.text('NoteFlow / Home'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('1 note'), findsOneWidget);
    });

    testWidgets('renders Vietnamese labels when the locale is vi', (
      WidgetTester tester,
    ) async {
      final List<NoteDto> notes = <NoteDto>[_buildNote(id: 'a')];
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery(_overview(notes: notes)),
      );

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: _FakeNotesController(notes: notes),
        locale: const Locale('vi'),
      );
      await tester.pumpAndSettle();

      expect(find.text('NoteFlow / Trang chủ'), findsOneWidget);
      expect(find.text('Trang chủ'), findsOneWidget);
      expect(find.text('1 ghi chú'), findsOneWidget);
    });

    testWidgets('survives concurrent overview load calls', (
      WidgetTester tester,
    ) async {
      final Completer<DashboardOverview> completer =
          Completer<DashboardOverview>();
      final DashboardController controller = DashboardController(
        query: _FakeDashboardQuery.pending(completer),
      );
      final List<NoteDto> notes = <NoteDto>[_buildNote(id: 'a')];

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: _FakeNotesController(notes: notes),
      );
      await tester.pump();

      final Future<DashboardState> first = controller.load();
      final Future<DashboardState> second = controller.load();
      completer.complete(_overview(notes: notes));
      await tester.pumpAndSettle();
      await first;
      await second;

      expect(tester.takeException(), isNull);
      expect(find.byType(DashboardNoteCard), findsOneWidget);
    });

    testWidgets('reload reads fresh notes and overview data', (
      WidgetTester tester,
    ) async {
      final NoteDto first = _buildNote(id: 'a', title: 'Alpha');
      final NoteDto added = _buildNote(id: 'b', title: 'Beta');
      final _FakeNotesController notesController = _FakeNotesController(
        notes: <NoteDto>[first],
      );
      final _FakeDashboardQuery query = _FakeDashboardQuery(
        _overview(notes: <NoteDto>[first]),
      );
      final DashboardController controller = DashboardController(query: query);

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: notesController,
      );
      await tester.pumpAndSettle();

      expect(find.byType(DashboardNoteCard), findsOneWidget);
      expect(find.text('Beta'), findsNothing);
      final int notesCallsBefore = notesController.listNotesCalls;
      final int queryCallsBefore = query.calls;

      // The data behind the already-mounted page changes.
      notesController.notes.add(added);
      query.result = _overview(notes: <NoteDto>[first, added]);

      final DashboardPageState page = tester.state<DashboardPageState>(
        find.byType(DashboardPage),
      );
      await page.reload();
      await tester.pumpAndSettle();

      expect(notesController.listNotesCalls, greaterThan(notesCallsBefore));
      expect(query.calls, greaterThan(queryCallsBefore));
      expect(find.byType(DashboardNoteCard), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('dashboard-note-b')),
          matching: find.text('Beta'),
        ),
        findsOneWidget,
      );
      expect(find.text('2 notes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shares an in-flight reload instead of repeating the request', (
      WidgetTester tester,
    ) async {
      final NoteDto first = _buildNote(id: 'a', title: 'Alpha');
      final NoteDto added = _buildNote(id: 'b', title: 'Beta');
      final _FakeNotesController notesController = _FakeNotesController(
        notes: <NoteDto>[first],
      );
      final _FakeDashboardQuery query = _FakeDashboardQuery(
        _overview(notes: <NoteDto>[first]),
      );
      final DashboardController controller = DashboardController(query: query);

      await _pumpDashboard(
        tester,
        dashboardController: controller,
        notesController: notesController,
      );
      await tester.pumpAndSettle();

      final int notesCallsBefore = notesController.listNotesCalls;
      final int queryCallsBefore = query.calls;

      // Hold the next request open so both reloads overlap.
      final Completer<void> gate = Completer<void>();
      notesController.listNotesGate = gate;
      notesController.notes.add(added);
      query.result = _overview(notes: <NoteDto>[first, added]);

      final DashboardPageState page = tester.state<DashboardPageState>(
        find.byType(DashboardPage),
      );
      final Future<void> firstReload = page.reload();
      final Future<void> secondReload = page.reload();
      await tester.pump();

      // The second reload joined the first request instead of issuing its own.
      expect(notesController.listNotesCalls, notesCallsBefore + 1);
      expect(query.calls, queryCallsBefore + 1);

      gate.complete();
      await tester.pumpAndSettle();
      await firstReload;
      await secondReload;

      // One shared request still delivers the fresh data to both callers.
      expect(notesController.listNotesCalls, notesCallsBefore + 1);
      expect(query.calls, queryCallsBefore + 1);
      expect(find.byType(DashboardNoteCard), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('dashboard-note-b')),
          matching: find.text('Beta'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required DashboardController dashboardController,
  required NotesApplicationController notesController,
  ValueChanged<NoteDto>? onOpenNote,
  FutureOr<NoteDetailRouteResult?> Function(NoteDto)? onOpenNoteResult,
  VoidCallback? onCreateNote,
  VoidCallback? onOpenSettings,
  VoidCallback? onOpenDiagnostics,
  bool embeddedInWorkspace = false,
  Locale locale = const Locale('en'),
  Size size = const Size(1200, 900),
  double textScale = 1.0,
  ValueChanged<bool>? onSearchVisibilityChanged,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        DashboardCopy.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
      home: Builder(
        builder: (BuildContext context) {
          final Widget page = DashboardPage(
            dashboardController: dashboardController,
            notesController: notesController,
            onOpenNote:
                onOpenNoteResult ??
                (onOpenNote == null
                    ? (NoteDto _) => null
                    : (NoteDto note) {
                        onOpenNote(note);
                        return null;
                      }),
            onCreateNote: onCreateNote == null
                ? () => null
                : () {
                    onCreateNote();
                    return null;
                  },
            embeddedInWorkspace: embeddedInWorkspace,
            onOpenSettings: onOpenSettings,
            onOpenDiagnostics: onOpenDiagnostics,
            onSearchVisibilityChanged: onSearchVisibilityChanged,
          );
          return MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: page,
          );
        },
      ),
    ),
  );
}

DashboardNoteCard _cardFor(WidgetTester tester, String id) {
  return tester.widget<DashboardNoteCard>(
    find.byKey(ValueKey<String>('dashboard-note-$id')),
  );
}

NoteDto _buildNote({
  String id = 'note-1',
  String title = 'First note',
  String content = 'First note body.',
  DateTime? updatedAt,
  DateTime? createdAt,
}) {
  return NoteDto(
    id: id,
    ownerId: 'local-user',
    title: title,
    content: content,
    createdAt: createdAt ?? _baseTime,
    updatedAt: updatedAt ?? _baseTime,
  );
}

DashboardOverview _overview({required List<NoteDto> notes}) {
  return DashboardOverview(
    totalNotes: notes.length,
    recentNotes: notes,
    lastUpdatedAt: notes.isEmpty ? null : notes.first.updatedAt,
  );
}

final class _FakeDashboardQuery implements IDashboardOverviewQuery {
  _FakeDashboardQuery(this.result) : _pending = null;

  _FakeDashboardQuery.pending(Completer<DashboardOverview> completer)
    : result = null,
      _pending = completer;

  DashboardOverview? result;
  final Completer<DashboardOverview>? _pending;
  Object? error;
  int calls = 0;

  @override
  Future<DashboardOverview> execute({required int recentLimit}) async {
    calls++;
    final Object? failure = error;
    if (failure != null) {
      throw failure;
    }
    final Completer<DashboardOverview>? pending = _pending;
    if (pending != null) {
      return pending.future;
    }
    return result!;
  }
}

final class _FakeNotesController implements NotesApplicationController {
  @override
  SummaryConsentAppService? get summaryConsent => null;

  _FakeNotesController({List<NoteDto>? notes, this.listNotesError})
    : notes = List<NoteDto>.of(notes ?? const <NoteDto>[]);

  final List<NoteDto> notes;
  final Object? listNotesError;

  /// When set, [listNotes] stays pending until the completer completes so a
  /// test can observe the page while a reload request is in flight.
  Completer<void>? listNotesGate;

  /// Number of [listNotes] calls, used to prove reloads are coalesced.
  int listNotesCalls = 0;

  @override
  Future<List<NoteDto>> listNotes() async {
    listNotesCalls++;
    final Completer<void>? gate = listNotesGate;
    if (gate != null) {
      await gate.future;
    }
    final Object? error = listNotesError;
    if (error != null) {
      throw error;
    }
    return List<NoteDto>.of(notes);
  }

  @override
  Future<NoteDto> createNote({required String title, required String content}) {
    throw UnimplementedError();
  }

  @override
  Future<NoteDto> renameNote({required String noteId, required String title}) {
    throw UnimplementedError();
  }

  @override
  Future<NoteDto> replaceContent({
    required String noteId,
    required String content,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteNote(String noteId) {
    throw UnimplementedError();
  }

  @override
  Future<String> summarizeNote(
    String noteId, {
    NoteDto? selectedSnapshot,
    SummaryRunScope? scope,
  }) {
    throw UnimplementedError();
  }
}
