import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/common/note_flow_primitives.dart';
import 'package:note_ai_app/presentation/notes/note_detail_action_bar.dart';
import 'package:note_ai_app/presentation/notes/notes_theme_tokens.dart';
import 'package:note_ai_app/presentation/workspace/workspace_localizations.dart';
import 'package:note_ai_app/presentation/workspace/workspace_shell.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      extensions: <ThemeExtension<dynamic>>[NoteFlowUiTokens.light()],
    ),
    home: Scaffold(body: child),
  );
}

void main() {
  group('accessibility labels', () {
    testWidgets('action bar exposes human labels without internal keys', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          NoteDetailActionBar(
            isSaving: false,
            isSummarizing: false,
            canSave: true,
            canSummarize: true,
            onSave: () {},
            onSummarize: () {},
            onMore: () {},
            saveLabel: 'Save note',
            summarizeLabel: 'Summarize note',
            moreLabel: 'More',
            savingLabel: 'Saving…',
            summarizingLabel: 'Summarizing…',
          ),
        ),
      );

      expect(find.text('Save note'), findsOneWidget);
      expect(find.text('Summarize note'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);

      expect(find.bySemanticsLabel(RegExp('Save note')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Summarize note')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('note-detail-')), findsNothing);
      handle.dispose();
    });

    testWidgets('menu items expose button semantics and labels', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          NoteFlowMenuItem(
            label: 'Delete note',
            icon: Icons.delete_outline,
            destructive: true,
            onTap: () {},
          ),
        ),
      );
      expect(find.bySemanticsLabel('Delete note'), findsOneWidget);
      handle.dispose();
    });
  });

  group('icon-only controls', () {
    testWidgets('shell icon buttons carry tooltips', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            WorkspaceCopy.delegate,
          ],
          home: WorkspaceShell(
            dashboard: const SizedBox(),
            notes: const SizedBox(),
            onOpenSettings: () {},
            onOpenDiagnostics: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Collapse sidebar'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
      expect(find.byTooltip('Diagnostics'), findsOneWidget);
    });
  });
}
