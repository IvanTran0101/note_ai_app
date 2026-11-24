import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/presentation/editor/editor_value_dialog.dart';
import 'package:note_ai_app/presentation/workspace/workspace_localizations.dart';
import 'package:note_ai_app/presentation/workspace/workspace_shell.dart';

const Key _dashboardKey = ValueKey<String>('ui43-safe-audit-dashboard');
const Key _notesKey = ValueKey<String>('ui43-safe-audit-notes');
const Key _editorRailKey = ValueKey<String>('ui43-safe-audit-editor-rail');
const Key _openEquationKey = ValueKey<String>('ui43-safe-audit-open-equation');

typedef _SafeAreaScenario = ({
  String name,
  Size size,
  _SyntheticInsets insets,
  bool editor,
});

void main() {
  testWidgets(
    'synthetic iOS cutout and Home Indicator insets contain shell actions',
    (WidgetTester tester) async {
      const _SyntheticInsets insets = _SyntheticInsets(
        padding: EdgeInsets.fromLTRB(34, 59, 34, 34),
        viewPadding: EdgeInsets.fromLTRB(34, 59, 34, 34),
        viewInsets: EdgeInsets.zero,
        systemGestureInsets: EdgeInsets.zero,
      );
      await _pumpCompactShell(
        tester,
        size: const Size(390, 844),
        insets: insets,
      );

      final Rect topControl = tester.getRect(
        find.byKey(WorkspaceShell.compactAvatarKey),
      );
      final Rect search = tester.getRect(
        find.byKey(WorkspaceShell.compactSearchKey),
      );
      final Rect create = tester.getRect(
        find.byKey(WorkspaceShell.compactFabNewNoteKey),
      );
      final Rect page = tester.getRect(find.byKey(_dashboardKey));

      expect(topControl.top, greaterThanOrEqualTo(59));
      expect(search.left, greaterThanOrEqualTo(34));
      expect(search.bottom, lessThanOrEqualTo(844 - 34));
      expect(create.right, lessThanOrEqualTo(390 - 34));
      expect(page.bottom, lessThanOrEqualTo(search.top));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'compact actions stay above synthetic Android navigation and IME insets',
    (WidgetTester tester) async {
      const List<_SafeAreaScenario> cases = <_SafeAreaScenario>[
        (
          name: 'three-button portrait',
          size: Size(390, 844),
          insets: _SyntheticInsets(
            padding: EdgeInsets.fromLTRB(0, 24, 0, 24),
            viewPadding: EdgeInsets.fromLTRB(0, 24, 0, 24),
            viewInsets: EdgeInsets.zero,
            systemGestureInsets: EdgeInsets.zero,
          ),
          editor: false,
        ),
        (
          name: 'three-button landscape',
          size: Size(844, 390),
          insets: _SyntheticInsets(
            padding: EdgeInsets.fromLTRB(0, 24, 0, 24),
            viewPadding: EdgeInsets.fromLTRB(0, 24, 0, 24),
            viewInsets: EdgeInsets.zero,
            systemGestureInsets: EdgeInsets.zero,
          ),
          editor: false,
        ),
        (
          name: 'gesture portrait',
          size: Size(390, 844),
          insets: _SyntheticInsets(
            padding: EdgeInsets.fromLTRB(0, 24, 0, 16),
            viewPadding: EdgeInsets.fromLTRB(0, 24, 0, 16),
            viewInsets: EdgeInsets.zero,
            systemGestureInsets: EdgeInsets.only(bottom: 16),
          ),
          editor: false,
        ),
        (
          name: 'gesture landscape',
          size: Size(844, 390),
          insets: _SyntheticInsets(
            padding: EdgeInsets.fromLTRB(0, 24, 0, 16),
            viewPadding: EdgeInsets.fromLTRB(0, 24, 0, 16),
            viewInsets: EdgeInsets.zero,
            systemGestureInsets: EdgeInsets.only(bottom: 16),
          ),
          editor: false,
        ),
        (
          name: 'three-button IME portrait',
          size: Size(390, 844),
          insets: _SyntheticInsets(
            padding: EdgeInsets.only(top: 24),
            viewPadding: EdgeInsets.fromLTRB(0, 24, 0, 24),
            viewInsets: EdgeInsets.only(bottom: 280),
            systemGestureInsets: EdgeInsets.zero,
          ),
          editor: true,
        ),
        (
          name: 'three-button IME landscape',
          size: Size(844, 390),
          insets: _SyntheticInsets(
            padding: EdgeInsets.only(top: 24),
            viewPadding: EdgeInsets.fromLTRB(0, 24, 0, 24),
            viewInsets: EdgeInsets.only(bottom: 150),
            systemGestureInsets: EdgeInsets.zero,
          ),
          editor: true,
        ),
        (
          name: 'gesture IME portrait',
          size: Size(390, 844),
          insets: _SyntheticInsets(
            padding: EdgeInsets.only(top: 24),
            viewPadding: EdgeInsets.fromLTRB(0, 24, 0, 16),
            viewInsets: EdgeInsets.only(bottom: 280),
            systemGestureInsets: EdgeInsets.only(bottom: 16),
          ),
          editor: true,
        ),
        (
          name: 'gesture IME landscape',
          size: Size(844, 390),
          insets: _SyntheticInsets(
            padding: EdgeInsets.only(top: 24),
            viewPadding: EdgeInsets.fromLTRB(0, 24, 0, 16),
            viewInsets: EdgeInsets.only(bottom: 150),
            systemGestureInsets: EdgeInsets.only(bottom: 16),
          ),
          editor: true,
        ),
      ];

      for (final scenario in cases) {
        final GlobalKey<WorkspaceShellState> shellKey =
            GlobalKey<WorkspaceShellState>();
        var editorRailCalls = 0;
        await _pumpCompactShell(
          tester,
          size: scenario.size,
          insets: scenario.insets,
          shellKey: shellKey,
          notesPage: scenario.editor
              ? _editorPage(onAction: () => editorRailCalls++)
              : null,
          initialDestination: scenario.editor
              ? WorkspaceDestination.notes
              : WorkspaceDestination.dashboard,
        );
        if (scenario.editor) {
          shellKey.currentState!.setNoteEditorActive(true);
          await tester.pumpAndSettle();
        }

        final Rect page = tester.getRect(
          find.byKey(scenario.editor ? _notesKey : _dashboardKey),
        );

        if (scenario.editor) {
          final double keyboardTop =
              scenario.size.height - scenario.insets.viewInsets.bottom;
          final Finder railFinder = find.byKey(_editorRailKey);
          final Rect rail = tester.getRect(railFinder);
          expect(
            find.byKey(WorkspaceShell.compactBottomNavigationKey),
            findsNothing,
            reason:
                '${scenario.name}: shell navigation should yield to editor controls',
          );
          expect(
            page.bottom,
            lessThanOrEqualTo(keyboardTop),
            reason: '${scenario.name}: editor page extends under the IME',
          );
          expect(
            rail.bottom,
            lessThanOrEqualTo(keyboardTop),
            reason: '${scenario.name}: editor rail intersects the IME',
          );
          expect(tester.getSize(railFinder).height, greaterThanOrEqualTo(48));
          expect(railFinder.hitTestable(), findsOneWidget);
          await tester.tap(railFinder);
          expect(editorRailCalls, 1);
        } else {
          final Rect action = tester.getRect(
            find.byKey(WorkspaceShell.compactSearchKey),
          );
          expect(
            action.bottom,
            lessThanOrEqualTo(
              scenario.size.height - scenario.insets.padding.bottom,
            ),
            reason:
                '${scenario.name}: compact search action intersects a system inset',
          );
          expect(
            page.bottom,
            lessThanOrEqualTo(action.top),
            reason: '${scenario.name}: page overlaps the compact action row',
          );
        }
        expect(tester.takeException(), isNull, reason: scenario.name);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('compact search and create actions expose accessible labels', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pumpCompactShell(
      tester,
      size: const Size(390, 844),
      insets: const _SyntheticInsets(
        padding: EdgeInsets.only(top: 24, bottom: 24),
        viewPadding: EdgeInsets.only(top: 24, bottom: 24),
        viewInsets: EdgeInsets.zero,
        systemGestureInsets: EdgeInsets.zero,
      ),
    );

    final WorkspaceCopy copy = WorkspaceCopy.of(
      tester.element(find.byKey(WorkspaceShell.compactSearchKey)),
    );
    final SemanticsData search = tester
        .getSemantics(find.byKey(WorkspaceShell.compactSearchKey))
        .getSemanticsData();
    final SemanticsData create = tester
        .getSemantics(find.byKey(WorkspaceShell.compactFabNewNoteKey))
        .getSemanticsData();
    expect(search.hasAction(SemanticsAction.tap), isTrue);
    expect(search.label, contains(copy.search));
    expect(create.hasAction(SemanticsAction.tap), isTrue);
    expect(create.label, contains(copy.newNote));
    semantics.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'editor equation dialog fits above a short landscape IME at large text',
    (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(844, 390)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const EdgeInsets viewPadding = EdgeInsets.fromLTRB(0, 24, 0, 24);
      const EdgeInsets viewInsets = EdgeInsets.only(bottom: 150);

      await tester.pumpWidget(
        MaterialApp(
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(top: 24),
              viewPadding: viewPadding,
              viewInsets: viewInsets,
              systemGestureInsets: const EdgeInsets.only(bottom: 16),
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: TextButton(
                  key: _openEquationKey,
                  onPressed: () {
                    unawaited(
                      editorValueDialog(
                        context,
                        title: 'Equation',
                        initial: r'\frac{1}{2}',
                        label: 'Equation',
                        validate: (_) {},
                        equation: true,
                      ),
                    );
                  },
                  child: const Text('Open equation dialog'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(_openEquationKey));
      await tester.pumpAndSettle();

      final Finder surface = find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Material),
          )
          .first;
      final Rect dialog = tester.getRect(surface);
      expect(dialog.top, greaterThanOrEqualTo(24));
      expect(dialog.bottom, lessThanOrEqualTo(390 - viewInsets.bottom));
      expect(find.text('Apply').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

Future<void> _pumpCompactShell(
  WidgetTester tester, {
  required Size size,
  required _SyntheticInsets insets,
  GlobalKey<WorkspaceShellState>? shellKey,
  Widget? notesPage,
  WorkspaceDestination initialDestination = WorkspaceDestination.dashboard,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: insets.padding,
          viewPadding: insets.viewPadding,
          viewInsets: insets.viewInsets,
          systemGestureInsets: insets.systemGestureInsets,
        ),
        child: child!,
      ),
      supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        WorkspaceCopy.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: WorkspaceShell(
        key: shellKey,
        initialDestination: initialDestination,
        dashboard: const SizedBox.expand(key: _dashboardKey),
        notes: notesPage ?? const SizedBox.expand(key: _notesKey),
        onOpenSearch: () {},
        onCreateNote: () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _editorPage({required VoidCallback onAction}) => SizedBox.expand(
  key: _notesKey,
  child: Column(
    children: <Widget>[
      const Expanded(child: SizedBox.expand()),
      IconButton(
        key: _editorRailKey,
        tooltip: 'Editor action',
        onPressed: onAction,
        icon: const Icon(Icons.undo),
      ),
    ],
  ),
);

final class _SyntheticInsets {
  const _SyntheticInsets({
    required this.padding,
    required this.viewPadding,
    required this.viewInsets,
    required this.systemGestureInsets,
  });

  final EdgeInsets padding;
  final EdgeInsets viewPadding;
  final EdgeInsets viewInsets;
  final EdgeInsets systemGestureInsets;
}
