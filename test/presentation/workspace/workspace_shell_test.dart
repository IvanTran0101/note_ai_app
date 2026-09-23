import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/presentation/workspace/workspace_localizations.dart';
import 'package:note_ai_app/presentation/workspace/workspace_shell.dart';

const ValueKey<String> _dashboardPageKey = ValueKey<String>('dashboard-page');
const ValueKey<String> _notesPageKey = ValueKey<String>('notes-page');

void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    required Size size,
    WorkspaceDestination initialDestination = WorkspaceDestination.dashboard,
    ValueChanged<WorkspaceDestination>? onDestinationChanged,
    VoidCallback? onOpenSearch,
    VoidCallback? onCreateNote,
    VoidCallback? onOpenSettings,
    VoidCallback? onOpenDiagnostics,
    Key? shellKey,
    Locale locale = const Locale('en'),
    Widget? dashboardPage,
    Widget? notesPage,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          WorkspaceCopy.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: WorkspaceShell(
          key: shellKey,
          dashboard:
              dashboardPage ??
              const _StubPage(key: _dashboardPageKey, label: 'Dashboard page'),
          notes:
              notesPage ??
              const _StubPage(key: _notesPageKey, label: 'Notes page'),
          initialDestination: initialDestination,
          onDestinationChanged: onDestinationChanged,
          onOpenSearch: onOpenSearch,
          onCreateNote: onCreateNote,
          onOpenSettings: onOpenSettings,
          onOpenDiagnostics: onOpenDiagnostics,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  int stackIndex(WidgetTester tester) {
    return tester.widget<IndexedStack>(find.byType(IndexedStack)).index!;
  }

  testWidgets('starts on the dashboard destination', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester, size: const Size(1000, 800));

    expect(stackIndex(tester), 0);
    expect(find.text('Dashboard page').hitTestable(), findsOneWidget);
    expect(find.text('Notes page').hitTestable(), findsNothing);
  });

  testWidgets('keeps an active note draft while crossing shell breakpoints', (
    WidgetTester tester,
  ) async {
    await pumpShell(
      tester,
      size: const Size(1280, 800),
      initialDestination: WorkspaceDestination.notes,
      notesPage: const _DraftPage(),
    );

    final Finder draft = find.byKey(_DraftPage.fieldKey);
    await tester.enterText(draft, 'Keep this draft');
    expect(tester.widget<TextField>(draft).controller!.text, 'Keep this draft');

    for (final Size size in <Size>[
      const Size(390, 844),
      const Size(768, 1024),
      const Size(1280, 800),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(draft).controller!.text,
        'Keep this draft',
      );
    }
  });

  testWidgets('showDestination switches to notes and keeps both pages alive', (
    WidgetTester tester,
  ) async {
    final GlobalKey<WorkspaceShellState> shellKey =
        GlobalKey<WorkspaceShellState>();
    await pumpShell(tester, size: const Size(1000, 800), shellKey: shellKey);

    expect(shellKey.currentState!.destination, WorkspaceDestination.dashboard);

    shellKey.currentState!.showDestination(WorkspaceDestination.notes);
    await tester.pumpAndSettle();

    expect(shellKey.currentState!.destination, WorkspaceDestination.notes);
    expect(stackIndex(tester), 1);
    expect(find.text('Notes page').hitTestable(), findsOneWidget);
    // The dashboard page is still mounted even though it is not visible.
    expect(find.text('Dashboard page', skipOffstage: false), findsOneWidget);
    expect(find.byKey(_dashboardPageKey, skipOffstage: false), findsOneWidget);
  });

  testWidgets('tapping a navigation item switches destination and notifies', (
    WidgetTester tester,
  ) async {
    final List<WorkspaceDestination> changes = <WorkspaceDestination>[];
    await pumpShell(
      tester,
      size: const Size(1000, 800),
      onDestinationChanged: changes.add,
    );

    await tester.tap(find.byKey(WorkspaceShell.notesDestinationKey));
    await tester.pumpAndSettle();

    expect(changes, <WorkspaceDestination>[WorkspaceDestination.notes]);
    expect(stackIndex(tester), 1);
    expect(find.text('Notes page').hitTestable(), findsOneWidget);
  });

  testWidgets('notifies only when the active destination really changes', (
    WidgetTester tester,
  ) async {
    final List<WorkspaceDestination> changes = <WorkspaceDestination>[];
    final GlobalKey<WorkspaceShellState> shellKey =
        GlobalKey<WorkspaceShellState>();
    await pumpShell(
      tester,
      size: const Size(1200, 900),
      shellKey: shellKey,
      onDestinationChanged: changes.add,
    );

    // Re-selecting the active destination through the public API is a no-op.
    shellKey.currentState!.showDestination(WorkspaceDestination.dashboard);
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(stackIndex(tester), 0);

    // Tapping the already-active sidebar item is a no-op too.
    await tester.tap(find.byKey(WorkspaceShell.dashboardDestinationKey));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(stackIndex(tester), 0);

    // A real change notifies exactly once.
    await tester.tap(find.byKey(WorkspaceShell.notesDestinationKey));
    await tester.pumpAndSettle();
    expect(changes, <WorkspaceDestination>[WorkspaceDestination.notes]);
    expect(stackIndex(tester), 1);

    // Re-selecting the now-active destination does not notify again.
    await tester.tap(find.byKey(WorkspaceShell.notesDestinationKey));
    await tester.pumpAndSettle();
    expect(changes, <WorkspaceDestination>[WorkspaceDestination.notes]);

    // Switching back reports only the new destination.
    await tester.tap(find.byKey(WorkspaceShell.dashboardDestinationKey));
    await tester.pumpAndSettle();
    expect(changes, <WorkspaceDestination>[
      WorkspaceDestination.notes,
      WorkspaceDestination.dashboard,
    ]);
    expect(stackIndex(tester), 0);
  });

  testWidgets('re-selecting the active rail destination does not notify', (
    WidgetTester tester,
  ) async {
    final List<WorkspaceDestination> changes = <WorkspaceDestination>[];
    await pumpShell(
      tester,
      size: const Size(700, 900),
      onDestinationChanged: changes.add,
    );

    await tester.tap(find.byKey(WorkspaceShell.dashboardDestinationKey));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(stackIndex(tester), 0);

    await tester.tap(find.byKey(WorkspaceShell.notesDestinationKey));
    await tester.pumpAndSettle();
    expect(changes, <WorkspaceDestination>[WorkspaceDestination.notes]);
    expect(stackIndex(tester), 1);

    await tester.tap(find.byKey(WorkspaceShell.notesDestinationKey));
    await tester.pumpAndSettle();
    expect(changes, <WorkspaceDestination>[WorkspaceDestination.notes]);
    expect(stackIndex(tester), 1);
  });

  testWidgets('compact width hides navigation and fills with the page', (
    WidgetTester tester,
  ) async {
    final GlobalKey<WorkspaceShellState> shellKey =
        GlobalKey<WorkspaceShellState>();
    await pumpShell(tester, size: const Size(480, 900), shellKey: shellKey);

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byKey(WorkspaceShell.sidebarKey), findsNothing);
    expect(find.byKey(WorkspaceShell.notesDestinationKey), findsNothing);
    expect(find.text('Dashboard page').hitTestable(), findsOneWidget);
    expect(tester.getSize(find.byKey(_dashboardPageKey)).width, 480);

    shellKey.currentState!.showDestination(WorkspaceDestination.notes);
    await tester.pumpAndSettle();

    expect(find.text('Notes page').hitTestable(), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('medium width shows a labelled NavigationRail', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester, size: const Size(700, 900));

    final Finder rail = find.byKey(WorkspaceShell.navigationRailKey);
    expect(rail, findsOneWidget);
    expect(find.byKey(WorkspaceShell.sidebarKey), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(tester.widget<NavigationRail>(rail).selectedIndex, 0);
    // The rail is docked on the leading edge of the window.
    expect(tester.getTopRight(rail).dx, lessThan(350));
  });

  testWidgets('expanded width shows a labelled sidebar with an active item', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester, size: const Size(1200, 900));

    final Finder sidebar = find.byKey(WorkspaceShell.sidebarKey);
    expect(sidebar, findsOneWidget);
    expect(find.byKey(WorkspaceShell.navigationRailKey), findsNothing);
    expect(tester.getSize(sidebar).width, 280.0);
    expect(find.text('NoteFlow'), findsOneWidget);
    expect(find.text('Workspace'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Dashboard page').hitTestable(), findsOneWidget);
  });

  testWidgets('active destination is exposed as selected to accessibility', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpShell(tester, size: const Size(1200, 900));

    SemanticsNode dashboardNode = tester.getSemantics(
      find.byKey(WorkspaceShell.dashboardDestinationKey),
    );
    SemanticsNode notesNode = tester.getSemantics(
      find.byKey(WorkspaceShell.notesDestinationKey),
    );
    expect(dashboardNode.label, 'Home');
    expect(dashboardNode.flagsCollection.isSelected.toBoolOrNull(), isTrue);
    expect(notesNode.flagsCollection.isSelected.toBoolOrNull(), isFalse);

    await tester.tap(find.byKey(WorkspaceShell.notesDestinationKey));
    await tester.pumpAndSettle();

    dashboardNode = tester.getSemantics(
      find.byKey(WorkspaceShell.dashboardDestinationKey),
    );
    notesNode = tester.getSemantics(
      find.byKey(WorkspaceShell.notesDestinationKey),
    );
    expect(notesNode.flagsCollection.isSelected.toBoolOrNull(), isTrue);
    expect(dashboardNode.flagsCollection.isSelected.toBoolOrNull(), isFalse);

    handle.dispose();
  });

  testWidgets('medium rail also exposes the selected destination', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpShell(tester, size: const Size(700, 900));

    expect(
      tester
          .getSemantics(find.byKey(WorkspaceShell.dashboardDestinationKey))
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isTrue,
    );
    expect(
      tester
          .getSemantics(find.byKey(WorkspaceShell.notesDestinationKey))
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isFalse,
    );

    handle.dispose();
  });

  testWidgets('renders Vietnamese labels from the localization delegate', (
    WidgetTester tester,
  ) async {
    await pumpShell(
      tester,
      size: const Size(1200, 900),
      locale: const Locale('vi'),
    );

    expect(find.text('Trang chủ'), findsOneWidget);
    expect(find.text('Ghi chú'), findsOneWidget);
    expect(find.text('NoteFlow'), findsOneWidget);
    expect(find.text('Không gian làm việc'), findsOneWidget);
  });

  testWidgets('sidebar quick actions delegate to existing callbacks', (
    WidgetTester tester,
  ) async {
    int searchCalls = 0;
    int createCalls = 0;
    await pumpShell(
      tester,
      size: const Size(1200, 900),
      onOpenSearch: () => searchCalls++,
      onCreateNote: () => createCalls++,
    );

    await tester.tap(find.byKey(WorkspaceShell.sidebarSearchKey));
    await tester.tap(find.byKey(WorkspaceShell.sidebarNewNoteKey));

    expect(searchCalls, 1);
    expect(createCalls, 1);
  });

  testWidgets('collapsing the sidebar keeps pages alive and restores', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester, size: const Size(1200, 900));
    expect(find.byKey(WorkspaceShell.sidebarKey), findsOneWidget);

    await tester.tap(find.byKey(WorkspaceShell.collapseToggleKey));
    await tester.pumpAndSettle();

    expect(find.byKey(WorkspaceShell.sidebarKey), findsNothing);
    expect(find.byKey(WorkspaceShell.collapsedSidebarKey), findsOneWidget);
    expect(
      tester.getSize(find.byKey(WorkspaceShell.collapsedSidebarKey)),
      Size.square(WorkspaceShell.collapsedSidebarWidth),
    );
    expect(
      tester.getTopLeft(find.byKey(WorkspaceShell.collapsedSidebarKey)),
      const Offset(0, WorkspaceShell.collapsedSidebarTopInset),
    );
    expect(tester.getSize(find.byKey(_dashboardPageKey)).width, 1200);
    expect(find.text('Dashboard page').hitTestable(), findsOneWidget);
    expect(find.byKey(WorkspaceShell.notesDestinationKey), findsNothing);

    await tester.tap(find.byKey(WorkspaceShell.collapseToggleKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(WorkspaceShell.notesDestinationKey));
    await tester.pumpAndSettle();
    expect(find.text('Notes page').hitTestable(), findsOneWidget);

    await tester.tap(find.byKey(WorkspaceShell.collapseToggleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(WorkspaceShell.collapsedSidebarKey), findsOneWidget);
    expect(find.text('Notes page').hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(WorkspaceShell.collapseToggleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(WorkspaceShell.sidebarKey), findsOneWidget);
    expect(find.byKey(WorkspaceShell.notesDestinationKey), findsOneWidget);
  });

  testWidgets('compact menu sheet switches destinations', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester, size: const Size(480, 900));
    expect(find.byKey(WorkspaceShell.compactMenuKey), findsOneWidget);

    await tester.tap(find.byKey(WorkspaceShell.compactMenuKey));
    await tester.pumpAndSettle();
    expect(find.byKey(WorkspaceShell.notesDestinationKey), findsOneWidget);

    await tester.tap(find.byKey(WorkspaceShell.notesDestinationKey));
    await tester.pumpAndSettle();
    expect(find.text('Notes page').hitTestable(), findsOneWidget);
  });

  testWidgets('footer settings and diagnostics fire their callbacks', (
    WidgetTester tester,
  ) async {
    bool settingsOpened = false;
    bool diagnosticsOpened = false;
    await pumpShell(
      tester,
      size: const Size(1200, 900),
      onOpenSettings: () => settingsOpened = true,
      onOpenDiagnostics: () => diagnosticsOpened = true,
    );

    await tester.tap(find.byKey(WorkspaceShell.settingsKey));
    await tester.pumpAndSettle();
    expect(settingsOpened, isTrue);

    await tester.tap(find.byKey(WorkspaceShell.diagnosticsKey));
    await tester.pumpAndSettle();
    expect(diagnosticsOpened, isTrue);
  });

  testWidgets('desktop footer labels existing actions with touch-sized rows', (
    WidgetTester tester,
  ) async {
    await pumpShell(
      tester,
      size: const Size(1200, 900),
      onOpenSettings: () {},
      onOpenDiagnostics: () {},
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Diagnostics'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(WorkspaceShell.settingsKey)).height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester.getSize(find.byKey(WorkspaceShell.diagnosticsKey)).height,
      greaterThanOrEqualTo(44),
    );
  });

  test('localization alias and delegate cover en and vi', () {
    expect(
      WorkspaceLocalizations.delegate.isSupported(const Locale('en')),
      isTrue,
    );
    expect(
      WorkspaceLocalizations.delegate.isSupported(const Locale('vi')),
      isTrue,
    );
  });
}

class _StubPage extends StatelessWidget {
  const _StubPage({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFFFFFFF),
      child: Center(child: Text(label)),
    );
  }
}

class _DraftPage extends StatefulWidget {
  const _DraftPage();

  static const Key fieldKey = ValueKey<String>('workspace-shell-draft-field');

  @override
  State<_DraftPage> createState() => _DraftPageState();
}

class _DraftPageState extends State<_DraftPage> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(key: _DraftPage.fieldKey, controller: _controller);
  }
}
