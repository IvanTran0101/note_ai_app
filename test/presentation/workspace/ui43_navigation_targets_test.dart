import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/workspace/workspace_localizations.dart';
import 'package:note_ai_app/presentation/workspace/workspace_shell.dart';

void main() {
  testWidgets('compact navigation pill margin remains a usable touch target', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shell = GlobalKey<WorkspaceShellState>();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [WorkspaceCopy.delegate],
        home: WorkspaceShell(
          key: shell,
          dashboard: const ColoredBox(
            color: Colors.white,
            key: ValueKey('home-page'),
          ),
          notes: const ColoredBox(
            color: Colors.white,
            key: ValueKey('notes-page'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final notes = find.byKey(const ValueKey('workspace-compact-notes'));
    final home = find.byKey(const ValueKey('workspace-compact-home'));
    final bounds = tester.getRect(notes);
    expect(bounds.height, 48);
    expect(bounds.width, greaterThanOrEqualTo(48));
    expect(tester.getRect(home).overlaps(bounds), isFalse);
    await tester.tapAt(Offset(bounds.center.dx, bounds.top + 1));
    await tester.pumpAndSettle();
    expect(shell.currentState!.destination, WorkspaceDestination.notes);
    expect(
      find.byKey(const ValueKey('notes-page')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
