import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PipelineOwner;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/common/note_flow_page_header.dart';
import 'package:note_ai_app/presentation/notes/note_detail_action_bar.dart';

void main() {
  for (final iconOnly in [false, true]) {
    testWidgets('one semantic action owner (icons: $iconOnly)', (tester) async {
      final handle = tester.ensureSemantics();
      var saves = 0, summaries = 0, more = 0;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NoteDetailActionBar(
                isSaving: false,
                isSummarizing: false,
                canSave: true,
                canSummarize: true,
                onSave: () => saves++,
                onSummarize: () => summaries++,
                onMore: null,
                onMoreWithContext: (_) => more++,
                saveLabel: 'Save',
                summarizeLabel: 'Summarize',
                moreLabel: 'More',
                savingLabel: 'Saving',
                summarizingLabel: 'Summarizing',
                summarizeTooltip: 'Create a summary',
                iconOnly: iconOnly,
              ),
            ),
          ),
        );
        final counts = <String, int>{};
        void visit(SemanticsNode node) {
          if (node.flagsCollection.isButton) {
            counts.update(node.label, (n) => n + 1, ifAbsent: () => 1);
          }
          node.visitChildren((child) {
            visit(child);
            return true;
          });
        }

        void visitOwner(PipelineOwner owner) {
          final root = owner.semanticsOwner?.rootSemanticsNode;
          if (root != null) visit(root);
          owner.visitChildren(visitOwner);
        }

        visitOwner(tester.binding.rootPipelineOwner);
        for (final name in ['Save', 'Summarize', 'More']) {
          expect(counts[name], 1, reason: '$name must be announced once');
        }
        for (final name in ['save', 'summarize', 'more']) {
          await tester.tap(find.byKey(ValueKey('note-detail-$name')));
        }
        expect([saves, summaries, more], [1, 1, 1]);
      } finally {
        handle.dispose();
      }
    });
  }

  testWidgets('wide page actions reach trailing edge without loose flex gap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteFlowPageHeader(
            breadcrumb: 'Notes / A long title',
            statusLabel: 'Saved locally',
            actions: [
              IconButton(
                key: const ValueKey('last-action'),
                onPressed: () {},
                icon: const Icon(Icons.more_horiz),
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      tester.getBottomRight(find.byKey(const ValueKey('last-action'))).dx,
      closeTo(1200, 1),
    );
    expect(tester.takeException(), isNull);
  });
}
