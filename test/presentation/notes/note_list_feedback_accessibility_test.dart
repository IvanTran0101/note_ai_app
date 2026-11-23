import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PipelineOwner;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/presentation/notes/animated_note_list.dart';
import 'package:note_ai_app/presentation/notes/note_detail_localizations.dart';
import 'package:note_ai_app/presentation/notes/note_summary_availability.dart';
import 'package:note_ai_app/presentation/notes/note_summary_feedback.dart';

void main() {
  for (final availability in [
    NoteSummaryAvailability.dirty,
    NoteSummaryAvailability.unavailable,
  ]) {
    testWidgets('one spoken summary notice: $availability', (tester) async {
      final handle = tester.ensureSemantics();
      String? expected;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  final copy = NoteDetailCopy.of(context);
                  expected = availability == NoteSummaryAvailability.dirty
                      ? copy.summarySavedRequired
                      : copy.summaryLocalUnavailable;
                  return NoteSummaryFeedback(
                    copy: copy,
                    availability: availability,
                    cloud: false,
                    isRunning: false,
                  );
                },
              ),
            ),
          ),
        );
        expect(
          tester
              .getSemantics(find.byKey(NoteSummaryFeedback.availabilityKey))
              .label,
          expected,
        );
      } finally {
        handle.dispose();
      }
    });
  }

  for (final readable in [true, false]) {
    testWidgets('one note-row action, masking retained: $readable', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final time = DateTime.utc(2026, 10, 17);
      final note = NoteDto(
        id: 'qa',
        ownerId: 'owner',
        title: 'Accessible note',
        content: 'Private body',
        createdAt: time,
        updatedAt: time,
      );
      var calls = 0;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AnimatedNoteList(
                notes: [note],
                selectedNoteId: note.reference,
                actionBusy: false,
                readable: (_) => readable,
                onSelectNote: (_) => calls++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final buttons = <SemanticsNode>[];
        void visit(SemanticsNode node) {
          if (node.flagsCollection.isButton) buttons.add(node);
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
        expect(buttons, hasLength(1));
        if (readable) {
          expect(buttons.single.label, contains('Accessible note'));
          expect(buttons.single.label, contains('Private body'));
        } else {
          expect(buttons.single.label, isNot(contains('Accessible note')));
          expect(buttons.single.label, isNot(contains('Private body')));
          expect(buttons.single.label, contains('Protected note'));
        }
        await tester.tap(find.byType(ListTile));
        expect(calls, 1);
      } finally {
        handle.dispose();
      }
    });
  }
}
