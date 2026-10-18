import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/editor/editor_icon_button.dart';

void main() {
  const key = ValueKey('action');
  final action = find.descendant(
    of: find.byKey(key),
    matching: find.byType(MergeSemantics),
  );
  testWidgets('visible tooltip does not merge into the action label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorIconButton(
              key: key,
              label: 'Add block',
              icon: const Icon(Icons.add),
              onPressed: () {},
            ),
          ),
        ),
      );
      tester.state<TooltipState>(find.byType(Tooltip)).ensureTooltipVisible();
      await tester.pumpAndSettle();
      expect(find.text('Add block'), findsOneWidget);
      expect(tester.getSemantics(action).label, 'Add block');
      var namedNodes = 0;
      void countLabels(SemanticsNode node) {
        if (node.label == 'Add block') namedNodes++;
        node.visitChildren((child) {
          countLabels(child);
          return true;
        });
      }

      countLabels(tester.getSemantics(action));
      expect(namedNodes, 1);
      // A Tooltip portal inside the merged action is aria-owned by its Web
      // button, duplicating the computed name while the tooltip is visible.
      expect(
        find.ancestor(
          of: find.byType(Tooltip),
          matching: find.byType(MergeSemantics),
        ),
        findsNothing,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('one action label excludes glyph and tooltip, full48 target', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: EditorIconButton(
                key: key,
                label: 'Callout style',
                icon: const Text('🎯'),
                onPressed: () => calls++,
              ),
            ),
          ),
        ),
      );
      expect(tester.getSemantics(action).label, 'Callout style');
      expect(
        tester.getSemantics(action),
        isSemantics(isButton: true, isEnabled: true, hasTapAction: true),
      );
      expect(tester.getSize(find.byKey(key)), const Size(48, 48));
      await tester.tapAt(
        tester.getBottomRight(find.byKey(key)) - const Offset(1, 1),
      );
      await tester.pump();
      expect(calls, 1);
      expect(tester.getSemantics(action).label, 'Callout style');
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('changed tooltip label is single and keyboard remains usable', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var expanded = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => Center(
                child: EditorIconButton(
                  key: key,
                  label: expanded ? 'Collapse toggle' : 'Expand toggle',
                  icon: Icon(
                    expanded ? Icons.expand_more : Icons.chevron_right,
                  ),
                  onPressed: () => update(() => expanded = !expanded),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      expect(expanded, isFalse);
      expect(tester.getSemantics(action).label, 'Expand toggle');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(expanded, isTrue);
      expect(tester.getSemantics(action).label, 'Collapse toggle');
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('disabled action has a label and refuses taps', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EditorIconButton(
              key: key,
              label: 'Undo',
              icon: Icon(Icons.undo),
              onPressed: null,
            ),
          ),
        ),
      );
      expect(tester.getSemantics(action).label, 'Undo');
      expect(
        tester.getSemantics(action),
        isSemantics(isButton: true, isEnabled: false, hasTapAction: false),
      );
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNull,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('decorative glyph retains icon metrics at large text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: EditorIconButton(
              label: 'Callout style',
              icon: const Text('🎯'),
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    expect(
      MediaQuery.textScalerOf(tester.element(find.text('🎯'))).scale(20),
      20,
    );
  });
}
