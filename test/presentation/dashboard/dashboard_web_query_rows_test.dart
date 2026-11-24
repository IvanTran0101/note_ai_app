import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/dashboard/dashboard_overview.dart';
import 'package:note_ai_app/application/notes/note_dto.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_content.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_localizations.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_note_card.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_view_models.dart';

void main() {
  testWidgets(
    'wide Web query results use a two-line row without changing order or pinning',
    (WidgetTester tester) async {
      final DateTime now = DateTime.now();
      final List<NoteDto> notes = <NoteDto>[
        _note(
          id: 'first',
          title: 'M09 UI reference first',
          updatedAt: now.add(const Duration(minutes: 1)),
        ),
        _note(id: 'second', title: 'M09 UI reference second', updatedAt: now),
      ];
      String? pinnedNoteId;

      await _pumpSearch(
        tester,
        notes: notes,
        query: 'M09 UI reference',
        onTogglePin: (NoteDto note) => pinnedNoteId = note.id,
      );

      final Finder firstCard = find.byKey(
        const ValueKey<String>('dashboard-note-card-first'),
      );
      final Finder secondCard = find.byKey(
        const ValueKey<String>('dashboard-note-card-second'),
      );
      expect(find.byType(DashboardNoteCard), findsNWidgets(2));
      expect(
        tester.getTopLeft(firstCard).dy,
        lessThan(tester.getTopLeft(secondCard).dy),
      );

      if (kIsWeb) {
        expect(find.text('Results'), findsOneWidget);
        expect(find.text('Today'), findsNothing);
        expect(tester.getSize(firstCard).height, 56);

        final Finder title = find.descendant(
          of: firstCard,
          matching: find.text('M09 UI reference first'),
        );
        final Finder preview = find.descendant(
          of: firstCard,
          matching: find.text('Local first preview'),
        );
        expect(title, findsOneWidget);
        expect(preview, findsOneWidget);
        expect(tester.widget<Text>(title).style?.fontSize, 14);
        expect(tester.widget<Text>(preview).style?.fontSize, 12);
      } else {
        expect(find.text('Today'), findsOneWidget);
        // The compact pin button raises this test theme's 38px row minimum.
        expect(tester.getSize(firstCard).height, 40);
        expect(
          find.descendant(
            of: firstCard,
            matching: find.text(
              'M09 UI reference first — Local first preview',
              findRichText: true,
            ),
          ),
          findsOneWidget,
        );
      }

      await tester.tap(
        find.descendant(of: firstCard, matching: find.byTooltip('Pin note')),
      );
      expect(pinnedNoteId, 'first');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty wide search history keeps its date heading', (
    WidgetTester tester,
  ) async {
    await _pumpSearch(
      tester,
      notes: <NoteDto>[_note(id: 'history', title: 'M09 UI reference')],
      query: '',
    );

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Results'), findsNothing);
    expect(find.byType(DashboardNoteCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Web query row keeps protected note text masked', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          DashboardCopy.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: DashboardNoteCard(
              key: const ValueKey<String>('dashboard-note-locked'),
              note: NoteDto(
                id: 'locked',
                ownerId: 'local-user',
                title: 'Secret title',
                content: 'Secret body',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
                isProtected: true,
                contentAvailable: false,
              ),
              readable: false,
              copy: DashboardCopy.of(context),
              layout: DashboardNoteCardLayout.list,
              onTap: (_) {},
              dense: true,
              webQueryResult: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Protected note'), findsOneWidget);
    expect(
      find.text('This note is locked. Unlock to read or edit.'),
      findsOneWidget,
    );
    expect(find.text('Secret title'), findsNothing);
    expect(find.text('Secret body'), findsNothing);
    final Semantics semantics = tester.widget<Semantics>(
      find.byKey(const ValueKey<String>('dashboard-note-semantics-locked')),
    );
    expect(semantics.properties.label, contains('Protected note'));
    expect(semantics.properties.label, isNot(contains('Secret')));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpSearch(
  WidgetTester tester, {
  required List<NoteDto> notes,
  required String query,
  ValueChanged<NoteDto>? onTogglePin,
}) async {
  tester.view.physicalSize = const Size(1280, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final TextEditingController searchController = TextEditingController(
    text: query,
  );
  addTearDown(searchController.dispose);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        DashboardCopy.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: DashboardContent(
            notes: notes,
            overview: DashboardOverview(
              totalNotes: notes.length,
              recentNotes: notes,
              lastUpdatedAt: notes.first.updatedAt,
            ),
            copy: DashboardCopy.of(context),
            searchController: searchController,
            searchOpen: true,
            searchText: query,
            layout: DashboardLayout.list,
            sort: DashboardSort.updated,
            selectedNoteId: null,
            hasError: false,
            onSearchChanged: (_) {},
            onClearSearch: () {},
            onSortChanged: (_) {},
            onLayoutChanged: (_) {},
            onOpenNote: (_) {},
            onTogglePin: onTogglePin,
            onCreateNote: () {},
            onRetry: () {},
            onRefresh: () async {},
            embeddedInWorkspace: true,
            onCloseSearch: () {},
            searchOverlay: true,
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
  DateTime? updatedAt,
}) {
  final DateTime now = updatedAt ?? DateTime.now();
  return NoteDto(
    id: id,
    ownerId: 'local-user',
    title: title,
    content: 'Local first preview',
    createdAt: now,
    updatedAt: now,
  );
}
