import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/common/note_flow_page_header.dart';
import 'package:note_ai_app/presentation/workspace/workspace_shell.dart';

void main() {
  testWidgets('collapsed sidebar shares header without covering Back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const backKey = ValueKey('header-back');
    var backCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceShell(
          initialDestination: WorkspaceDestination.notes,
          dashboard: const Text('Home'),
          notes: Column(
            children: [
              NoteFlowPageHeader(
                breadcrumb: 'Notes / Sample',
                backKey: backKey,
                onBack: () => backCalls++,
              ),
              const Expanded(child: TextField()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final inputState = tester.state(find.byType(TextField));
    await tester.tap(find.byKey(WorkspaceShell.collapseToggleKey));
    await tester.pumpAndSettle();
    final toggle = tester.getRect(
      find.byKey(WorkspaceShell.collapsedSidebarKey),
    );
    final back = tester.getRect(find.byKey(backKey));
    expect(toggle.top, 0);
    expect(toggle.right, lessThanOrEqualTo(back.left));
    expect(toggle.overlaps(back), isFalse);
    await tester.tap(find.byKey(backKey));
    expect(backCalls, 1);
    await tester.tap(find.byKey(WorkspaceShell.collapseToggleKey));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(TextField)), same(inputState));
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor owns slow pans while list retains page swipes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey<WorkspaceShellState>();
    var editorPanUpdates = 0;
    const canvasKey = ValueKey('selection-canvas');
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceShell(
          key: key,
          initialDestination: WorkspaceDestination.notes,
          dashboard: const Text('Home'),
          notes: GestureDetector(
            key: canvasKey,
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (_) => editorPanUpdates++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> slowHorizontalDrag() async {
      final start =
          tester.getTopLeft(find.byKey(canvasKey)) + const Offset(80, 200);
      final gesture = await tester.startGesture(start);
      for (var step = 1; step <= 55; step++) {
        await gesture.moveTo(start + Offset(step * 4, 0));
        await tester.pump(const Duration(milliseconds: 15));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    key.currentState!.setNoteEditorActive(true);
    await tester.pumpAndSettle();
    await slowHorizontalDrag();
    expect(editorPanUpdates, greaterThan(0));
    expect(key.currentState!.destination, WorkspaceDestination.notes);

    key.currentState!.setNoteEditorActive(false);
    await tester.pumpAndSettle();
    await slowHorizontalDrag();
    expect(key.currentState!.destination, WorkspaceDestination.dashboard);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone editor owns chrome without replacing its input state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey<WorkspaceShellState>();
    final controller = TextEditingController();
    var searches = 0;
    var creates = 0;
    var asks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceShell(
          key: key,
          initialDestination: WorkspaceDestination.notes,
          onOpenSearch: () => searches++,
          onCreateNote: () => creates++,
          onOpenRag: () => asks++,
          dashboard: const Text('Home'),
          notes: TextField(
            key: const ValueKey('draft'),
            controller: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(WorkspaceShell.compactAvatarKey), findsOneWidget);
    final state = tester.state(find.byKey(const ValueKey('draft')));
    await tester.enterText(find.byKey(const ValueKey('draft')), 'draft');
    key.currentState!.setNoteEditorActive(true);
    await tester.pumpAndSettle();
    expect(find.byKey(WorkspaceShell.compactAvatarKey), findsNothing);
    expect(
      find.byKey(WorkspaceShell.compactBottomNavigationKey),
      findsOneWidget,
    );
    await tester.tap(find.byKey(WorkspaceShell.compactSearchKey));
    await tester.tap(find.byKey(WorkspaceShell.compactFabNewNoteKey));
    await tester.tap(find.byKey(const ValueKey('workspace-bottom-ask-notes')));
    expect([searches, creates, asks], [1, 1, 1]);
    expect(tester.state(find.byKey(const ValueKey('draft'))), same(state));
    expect(controller.text, 'draft');
    key.currentState!.setNoteEditorActive(false);
    await tester.pumpAndSettle();
    expect(find.byKey(WorkspaceShell.compactAvatarKey), findsOneWidget);
    expect(
      find.byKey(WorkspaceShell.compactBottomNavigationKey),
      findsOneWidget,
    );
    expect(tester.state(find.byKey(const ValueKey('draft'))), same(state));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    expect(tester.takeException(), isNull);
  });
}
