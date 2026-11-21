import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/dashboard/dashboard_overview.dart';
import 'package:note_ai_app/application/dashboard/get_dashboard_overview.dart';
import 'package:note_ai_app/application/notes/note_dto.dart';
import 'package:note_ai_app/application/notes/note_page.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';
import 'package:note_ai_app/presentation/notes/notes_workspace_page.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_page.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_controller.dart';

class _Pages implements NotesApplicationController, PagedNotesController {
  final queries = <NotePageQuery>[];
  Future<NotePage> Function(NotePageQuery)? handler;
  bool fail = false;
  @override
  bool get notePaginationAvailable => true;
  @override
  Future<List<NoteDto>> listNotes() =>
      throw StateError('Full list must not load');
  @override
  Future<NotePage> listNotePage(NotePageQuery query) async {
    queries.add(query);
    if (fail) throw StateError('Synthetic read failure');
    if (handler != null) return handler!(query);
    return result(query);
  }

  NotePage result(NotePageQuery query) {
    final search = query.keyword.isNotEmpty;
    return NotePage(
      total: search ? 1 : 1000,
      page: search ? 0 : query.page,
      size: query.size,
      notes: List.generate(search ? 1 : query.size, (i) {
        final n = search ? 999 : query.page * query.size + i;
        return NoteDto(
          id: 'n$n',
          ownerId: 'actor',
          title: 'Note $n',
          content: 'Body $n',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );
      }),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Overview implements IDashboardOverviewQuery {
  @override
  Future<DashboardOverview> execute({required int recentLimit}) async =>
      DashboardOverview(
        totalNotes: 1000,
        recentNotes: const [],
        lastUpdatedAt: DateTime.utc(2026),
      );
}

class _SecuredPages extends _Pages implements SecuredNotesController {
  final events = StreamController<void>.broadcast(sync: true);
  int generation = 0;
  @override
  int get sessionGeneration => generation;
  @override
  Stream<void> get securityChanges => events.stream;
  @override
  NoteAccessCapabilities capabilitiesFor(NoteDto note) =>
      const NoteAccessCapabilities(canRead: true);
}

void main() {
  testWidgets(
    'Home drops old facets/content and late results across session change',
    (tester) async {
      final pages = _SecuredPages();
      final dashboard = DashboardController(query: _Overview());
      addTearDown(dashboard.dispose);
      addTearDown(pages.events.close);
      final key = GlobalKey<DashboardPageState>();
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardPage(
            key: key,
            dashboardController: dashboard,
            notesController: pages,
            onOpenNote: (_) async => null,
            onCreateNote: () async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final late = Completer<NotePage>();
      var pending = true;
      pages.handler = (q) => pending
          ? late.future
          : Future.value(
              pages.result(NotePageQuery(keyword: 'after', size: q.size)),
            );
      final reload = key.currentState!.reload();
      await tester.pump();
      pending = false;
      pages.generation++;
      pages.events.add(null);
      await tester.pumpAndSettle();
      expect(find.text('1–1 / 1'), findsOneWidget);
      late.complete(pages.result(NotePageQuery()));
      await reload;
      await tester.pumpAndSettle();
      expect(find.text('1–1 / 1'), findsOneWidget);
    },
  );

  testWidgets(
    'Home and search use global pages; late query cannot replace newer result',
    (tester) async {
      final pages = _Pages();
      final dashboard = DashboardController(query: _Overview());
      addTearDown(dashboard.dispose);
      final key = GlobalKey<DashboardPageState>();
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardPage(
            key: key,
            dashboardController: dashboard,
            notesController: pages,
            onOpenNote: (_) async => null,
            onCreateNote: () async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1–50 / 1000'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('notes-page-next')));
      await tester.pumpAndSettle();
      expect(find.text('51–100 / 1000'), findsOneWidget);
      key.currentState!.openSearch();
      await tester.pumpAndSettle();
      final late = Completer<NotePage>();
      pages.handler = (q) => q.keyword == 'old' && q.size == 50
          ? late.future
          : Future.value(pages.result(q));
      final field = find.byKey(const ValueKey('dashboard-search-field'));
      await tester.enterText(field, 'old');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.enterText(field, 'needle');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(find.text('1–1 / 1'), findsOneWidget);
      expect(
        pages.queries
            .where((q) => q.keyword == 'needle' && q.size == 50)
            .single
            .page,
        0,
      );
      late.complete(pages.result(NotePageQuery(page: 8)));
      await tester.pumpAndSettle();
      expect(find.text('1–1 / 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed page keeps current rows and Retry requests the intended page',
    (tester) async {
      final pages = _Pages();
      await tester.pumpWidget(
        MaterialApp(home: NotesWorkspacePage(controller: pages)),
      );
      await tester.pumpAndSettle();
      pages.fail = true;
      await tester.tap(find.byKey(const ValueKey('notes-page-next')));
      await tester.pumpAndSettle();
      expect(find.text('1–50 / 1000'), findsOneWidget);
      expect(find.byKey(const ValueKey('notes-list-error')), findsOneWidget);
      pages.fail = false;
      await tester.tap(find.byKey(const ValueKey('retry-notes')));
      await tester.pumpAndSettle();
      expect(find.text('51–100 / 1000'), findsOneWidget);
    },
  );

  testWidgets('Notes next/previous requests bounded pages, not the full list', (
    tester,
  ) async {
    final pages = _Pages();
    await tester.pumpWidget(
      MaterialApp(home: NotesWorkspacePage(controller: pages)),
    );
    await tester.pumpAndSettle();
    expect(find.text('1–50 / 1000'), findsOneWidget);
    expect(pages.queries.single.page, 0);
    await tester.tap(find.byKey(const ValueKey('notes-page-next')));
    await tester.pumpAndSettle();
    expect(find.text('51–100 / 1000'), findsOneWidget);
    expect(pages.queries.last.page, 1);
    expect(pages.queries.last.size, 50);
    await tester.tap(find.byKey(const ValueKey('notes-page-previous')));
    await tester.pumpAndSettle();
    expect(find.text('1–50 / 1000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
