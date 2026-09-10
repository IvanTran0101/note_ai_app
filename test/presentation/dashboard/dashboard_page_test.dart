import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/dashboard/dashboard_overview.dart';
import 'package:note_ai_app/application/dashboard/get_dashboard_overview.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_controller.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_localizations.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_note_card.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_page.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_state.dart';
import 'package:note_ai_app/presentation/notes/note_detail_route_result.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';

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

      expect(english.allNotes, 'All notes');
      expect(vietnamese.allNotes, 'Tất cả ghi chú');
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
      );
      await tester.pumpAndSettle();

      expect(find.byType(DashboardNoteCard), findsNWidgets(2));
      expect(find.text('All notes'), findsOneWidget);
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

      await tester.tap(find.byIcon(Icons.view_list_outlined));
      await tester.pumpAndSettle();

      expect(_cardFor(tester, 'a').layout, DashboardNoteCardLayout.list);
      expect(_cardFor(tester, 'b').layout, DashboardNoteCardLayout.list);
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

      final double compactA = tester
          .getTopLeft(find.byKey(const ValueKey<String>('dashboard-note-a')))
          .dy;
      final double compactB = tester
          .getTopLeft(find.byKey(const ValueKey<String>('dashboard-note-b')))
          .dy;
      expect(compactA, compactB);

      await tester.tap(find.byIcon(Icons.view_list_outlined));
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

        expect(find.text('Tất cả ghi chú'), findsOneWidget);
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

      final ThemeData theme = Theme.of(
        tester.element(find.byType(DashboardPage)),
      );
      final Text title = tester.widget<Text>(find.text('Alpha'));
      final Card card = tester.widget<Card>(
        find.byKey(const ValueKey<String>('dashboard-note-card-a')),
      );
      expect(card.color, theme.colorScheme.primaryContainer);
      expect(title.style?.color, theme.colorScheme.onPrimaryContainer);

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
      expect(find.text('Renamed'), findsOneWidget);
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

      expect(find.text('NoteFlow'), findsOneWidget);
      expect(find.text('All notes'), findsOneWidget);
      expect(find.text('1 note'), findsOneWidget);
      expect(find.text('NoteFlow'), findsOneWidget);
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

      expect(find.text('Tất cả ghi chú'), findsOneWidget);
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
  Locale locale = const Locale('en'),
  Size size = const Size(1200, 900),
  double textScale = 1.0,
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
            onOpenSettings: onOpenSettings,
            onOpenDiagnostics: onOpenDiagnostics,
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
  _FakeNotesController({List<NoteDto>? notes, this.listNotesError})
    : notes = List<NoteDto>.of(notes ?? const <NoteDto>[]);

  final List<NoteDto> notes;
  final Object? listNotesError;

  @override
  Future<List<NoteDto>> listNotes() async {
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
  Future<String> summarizeNote(String noteId) {
    throw UnimplementedError();
  }
}
