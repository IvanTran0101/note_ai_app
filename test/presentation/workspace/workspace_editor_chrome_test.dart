import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/workspace/workspace_shell.dart';

void main() {
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
