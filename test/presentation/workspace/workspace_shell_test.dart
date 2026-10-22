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
    bool disableAnimations = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
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

  testWidgets('phone resize releases desktop navigation on the first frame', (
    tester,
  ) async {
    double pageWidth = 0;
    await pumpShell(
      tester,
      size: const Size(1280, 844),
      dashboardPage: LayoutBuilder(
        builder: (context, constraints) {
          pageWidth = constraints.maxWidth;
          return const SizedBox.expand();
        },
      ),
    );
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    expect(pageWidth, 390);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
  });

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

  testWidgets('compact header matches the reference avatar and pill geometry', (
    WidgetTester tester,
  ) async {
    await pumpShell(
      tester,
      size: const Size(390, 844),
      onOpenSearch: () {},
      onCreateNote: () {},
    );

    final Finder avatar = find.descendant(
      of: find.byKey(WorkspaceShell.compactAvatarKey),
      matching: find.byType(CircleAvatar),
    );
    final Finder homePill = find.byKey(
      const ValueKey<String>('workspace-compact-home'),
    );
    expect(avatar, findsOneWidget);
    expect(tester.getTopLeft(avatar).dx, closeTo(21, 0.1));
    expect(tester.getSize(avatar), const Size(38, 38));
    expect(tester.getTopLeft(homePill).dx, closeTo(68, 0.1));
    expect(tester.getSize(homePill), const Size(64, 40));
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
    expect(tester.getSize(sidebar).width, 270.0);
    expect(find.text('NoteFlow'), findsOneWidget);
    expect(find.byKey(WorkspaceShell.notionBrandMarkKey), findsOneWidget);
    expect(find.text('Workspace'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Dashboard page').hitTestable(), findsOneWidget);
  });

  testWidgets('compact search hides the workspace top and bottom chrome', (
    WidgetTester tester,
  ) async {
    final GlobalKey<WorkspaceShellState> shellKey =
        GlobalKey<WorkspaceShellState>();
    await pumpShell(
      tester,
      size: const Size(390, 844),
      shellKey: shellKey,
      onOpenSearch: () {},
      onCreateNote: () {},
    );

    expect(find.byKey(WorkspaceShell.compactBrandKey), findsOneWidget);
    expect(
      find.byKey(WorkspaceShell.compactBottomNavigationKey),
      findsOneWidget,
    );

    shellKey.currentState!.setCompactSearchActive(true);
    await tester.pumpAndSettle();

    expect(find.byKey(WorkspaceShell.compactBrandKey), findsNothing);
    expect(find.byKey(WorkspaceShell.compactBottomNavigationKey), findsNothing);
    expect(find.text('Dashboard page').hitTestable(), findsOneWidget);

    shellKey.currentState!.setCompactSearchActive(false);
    await tester.pumpAndSettle();
    expect(find.byKey(WorkspaceShell.compactBrandKey), findsOneWidget);
    expect(
      find.byKey(WorkspaceShell.compactBottomNavigationKey),
      findsOneWidget,
    );
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final double movingWidth = tester
        .getSize(find.byKey(_dashboardPageKey))
        .width;
    expect(movingWidth, greaterThan(1200 - WorkspaceShell.sidebarWidth - 1));
    expect(movingWidth, lessThan(1200));
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
    expect(find.byKey(WorkspaceShell.notionBrandMarkKey), findsOneWidget);
    expect(find.byKey(WorkspaceShell.notesDestinationKey), findsOneWidget);

    await tester.tap(find.byKey(WorkspaceShell.notesDestinationKey));
    await tester.pumpAndSettle();
    expect(find.text('Notes page').hitTestable(), findsOneWidget);
  });

  testWidgets('reduce motion collapses sidebar immediately', (
    WidgetTester tester,
  ) async {
    await pumpShell(
      tester,
      size: const Size(1200, 900),
      disableAnimations: true,
    );
    await tester.tap(find.byKey(WorkspaceShell.collapseToggleKey));
    await tester.pump();
    expect(tester.getSize(find.byKey(_dashboardPageKey)).width, 1200);
    expect(find.byKey(WorkspaceShell.sidebarKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact shell keeps secondary actions in navigation menu', (
    WidgetTester tester,
  ) async {
    int searchCalls = 0;
    int createCalls = 0;
    int settingsCalls = 0;
    int diagnosticsCalls = 0;
    await pumpShell(
      tester,
      size: const Size(390, 844),
      onOpenSearch: () => searchCalls++,
      onCreateNote: () => createCalls++,
      onOpenSettings: () => settingsCalls++,
      onOpenDiagnostics: () => diagnosticsCalls++,
    );

    expect(find.byKey(WorkspaceShell.compactMenuKey), findsOneWidget);
    expect(find.byKey(WorkspaceShell.compactSearchKey), findsOneWidget);
    expect(find.byKey(WorkspaceShell.compactNewNoteKey), findsNothing);
    expect(find.byKey(WorkspaceShell.settingsKey), findsNothing);
    expect(find.byKey(WorkspaceShell.diagnosticsKey), findsNothing);

    await tester.tap(find.byKey(WorkspaceShell.compactMenuKey));
    await tester.pumpAndSettle();
    expect(find.byKey(WorkspaceShell.compactMenuSearchKey), findsOneWidget);
    expect(find.byKey(WorkspaceShell.compactNewNoteKey), findsOneWidget);
    expect(find.byKey(WorkspaceShell.compactMenuNewNoteKey), findsOneWidget);
    expect(find.byKey(WorkspaceShell.settingsKey), findsOneWidget);
    expect(find.byKey(WorkspaceShell.diagnosticsKey), findsOneWidget);

    await tester.tap(find.byKey(WorkspaceShell.compactMenuSearchKey));
    await tester.pumpAndSettle();
    expect(searchCalls, 1);

    await tester.tap(find.byKey(WorkspaceShell.compactMenuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(WorkspaceShell.compactMenuNewNoteKey));
    await tester.pumpAndSettle();
    expect(createCalls, 1);

    await tester.tap(find.byKey(WorkspaceShell.compactMenuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(WorkspaceShell.diagnosticsKey));
    await tester.pumpAndSettle();
    expect(diagnosticsCalls, 1);

    await tester.tap(find.byKey(WorkspaceShell.compactMenuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(WorkspaceShell.settingsKey));
    await tester.pumpAndSettle();
    expect(settingsCalls, 1);
  });

  testWidgets(
    'compact bottom icons call the existing search and create actions',
    (WidgetTester tester) async {
      int searchCalls = 0;
      int createCalls = 0;
      await pumpShell(
        tester,
        size: const Size(390, 844),
        onOpenSearch: () => searchCalls++,
        onCreateNote: () => createCalls++,
      );

      await tester.tap(find.byKey(WorkspaceShell.compactSearchKey));
      await tester.pumpAndSettle();
      expect(searchCalls, 1);
      expect(
        tester.getSize(find.byKey(WorkspaceShell.compactSearchKey)),
        const Size(48, 48),
      );
      expect(
        tester.getTopLeft(find.byKey(WorkspaceShell.compactSearchKey)).dx,
        closeTo(16, 0.1),
      );

      await tester.tap(find.byKey(WorkspaceShell.compactFabNewNoteKey));
      await tester.pumpAndSettle();
      expect(createCalls, 1);
      expect(
        tester.getSize(find.byKey(WorkspaceShell.compactFabNewNoteKey)),
        const Size(48, 48),
      );
      expect(
        tester.getTopLeft(find.byKey(WorkspaceShell.compactFabNewNoteKey)).dx,
        closeTo(326, 0.1),
      );
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets(
    'desktop footer labels existing actions with dense pointer rows',
    (WidgetTester tester) async {
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
        greaterThanOrEqualTo(32),
      );
      expect(
        tester.getSize(find.byKey(WorkspaceShell.diagnosticsKey)).height,
        greaterThanOrEqualTo(32),
      );
    },
  );

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
