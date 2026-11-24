// ignore: implementation_imports
import 'package:appflowy_editor/src/service/selection/selection_gesture.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const detectorKey = ValueKey<String>('selection-detector');
  const editableKey = ValueKey<String>('child-editable');
  const buttonKey = ValueKey<String>('child-button');
  const blankTapTargetKey = ValueKey<String>('blank-tap-target');

  testWidgets(
    'web excludes generic tap semantics, preserving child semantics and pointer taps',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final fieldFocus = FocusNode();
      var selectionTapDowns = 0;
      var buttonTaps = 0;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SelectionGestureDetector(
                  key: detectorKey,
                  onTapDown: (_) => selectionTapDowns++,
                  child: SizedBox(
                    width: 320,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          key: editableKey,
                          focusNode: fieldFocus,
                          decoration: const InputDecoration(
                            labelText: 'Editable',
                          ),
                        ),
                        ElevatedButton(
                          key: buttonKey,
                          onPressed: () => buttonTaps++,
                          child: const Text('Child button'),
                        ),
                        ColoredBox(
                          key: blankTapTargetKey,
                          color: Colors.transparent,
                          child: const SizedBox(height: 64),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        fieldFocus.requestFocus();
        await tester.pumpAndSettle();

        final genericSelectionSemantics = tester.getSemantics(
          find.byKey(detectorKey),
        );
        // Web should not expose the editor-wide generic tap node. Native keeps
        // its existing semantics behavior.
        expect(
          genericSelectionSemantics.getSemanticsData().hasAction(
            SemanticsAction.tap,
          ),
          !kIsWeb,
        );

        SemanticsNode? editableNode;
        void visit(SemanticsNode node) {
          if (node.flagsCollection.isTextField) editableNode = node;
          node.visitChildren((child) {
            visit(child);
            return true;
          });
        }

        visit(genericSelectionSemantics);
        expect(editableNode, isNotNull);
        final editableSemantics = editableNode!;
        expect(editableSemantics.flagsCollection.isTextField, isTrue);
        expect(
          editableSemantics.getSemanticsData().hasAction(
            SemanticsAction.setText,
          ),
          isTrue,
        );

        final buttonSemantics = tester.getSemantics(find.byKey(buttonKey));
        expect(buttonSemantics.label, 'Child button');
        expect(
          buttonSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );

        await tester.tapAt(tester.getCenter(find.byKey(blankTapTargetKey)));
        await tester.pump();
        expect(selectionTapDowns, 1);
        expect(buttonTaps, 0);
      } finally {
        await tester.pumpWidget(const SizedBox());
        fieldFocus.dispose();
        semantics.dispose();
      }
    },
  );
}
