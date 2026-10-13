import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/presentation/workspace/workspace_localizations.dart';
import 'package:note_ai_app/presentation/workspace/workspace_shell.dart';

const ValueKey<String> _dashboardPageKey = ValueKey<String>('dashboard-page');
const ValueKey<String> _notesPageKey = ValueKey<String>('notes-page');

/// Focused shell coverage for the optional account-wide ask-notes action.
///
/// The shell gains no destination and no state: the action is hidden when the
/// composition root supplies no callback and is available from the compact
/// menu, the medium rail, and the expanded sidebar when it does.
void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    required Size size,
    VoidCallback? onOpenRag,
    Locale locale = const Locale('en'),
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
          dashboard: const SizedBox(key: _dashboardPageKey),
          notes: const SizedBox(key: _notesPageKey),
          onOpenRag: onOpenRag,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('compact menu offers ask-notes only when wired', (tester) async {
    var opened = 0;
    await pumpShell(
      tester,
      size: const Size(400, 800),
      onOpenRag: () => opened++,
    );
    await tester.tap(find.byKey(WorkspaceShell.compactAvatarKey));
    await tester.pumpAndSettle();
    expect(find.byKey(WorkspaceShell.compactMenuAskNotesKey), findsOneWidget);
    await tester.tap(find.byKey(WorkspaceShell.compactMenuAskNotesKey));
    await tester.pumpAndSettle();
    expect(opened, 1);

    await pumpShell(tester, size: const Size(400, 800));
    await tester.tap(find.byKey(WorkspaceShell.compactAvatarKey));
    await tester.pumpAndSettle();
    expect(find.byKey(WorkspaceShell.compactMenuAskNotesKey), findsNothing);
  });

  testWidgets('medium rail exposes ask-notes only when wired', (tester) async {
    var opened = 0;
    await pumpShell(
      tester,
      size: const Size(700, 900),
      onOpenRag: () => opened++,
    );
    expect(find.byKey(WorkspaceShell.railAskNotesKey), findsOneWidget);
    await tester.tap(find.byKey(WorkspaceShell.railAskNotesKey));
    await tester.pumpAndSettle();
    expect(opened, 1);

    await pumpShell(tester, size: const Size(700, 900));
    expect(find.byKey(WorkspaceShell.railAskNotesKey), findsNothing);
  });

  testWidgets('expanded sidebar footer exposes ask-notes and localizes it', (
    tester,
  ) async {
    var opened = 0;
    await pumpShell(
      tester,
      size: const Size(1280, 800),
      onOpenRag: () => opened++,
    );
    expect(find.byKey(WorkspaceShell.askNotesKey), findsOneWidget);
    expect(find.text('Ask notes'), findsOneWidget);
    await tester.tap(find.byKey(WorkspaceShell.askNotesKey));
    await tester.pumpAndSettle();
    expect(opened, 1);

    await pumpShell(
      tester,
      size: const Size(1280, 800),
      onOpenRag: () {},
      locale: const Locale('vi'),
    );
    expect(find.text('Hỏi ghi chú'), findsOneWidget);
  });
}
