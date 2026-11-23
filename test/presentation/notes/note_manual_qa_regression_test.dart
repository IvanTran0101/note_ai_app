import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_dto.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_role.dart';
import 'package:note_ai_app/domain/notes/note_share_grant.dart';
import 'package:note_ai_app/presentation/notes/note_detail_action_bar.dart';
import 'package:note_ai_app/presentation/notes/note_security_panel.dart';
import 'package:note_ai_app/presentation/common/note_flow_primitives.dart';

void main() {
  testWidgets('save status keeps its semantics identity through animation', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var label = 'Saved locally';
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setter) {
            update = setter;
            return Material(
              child: NoteFlowPageHeader(
                breadcrumb: 'Notes',
                statusLabel: label,
              ),
            );
          },
        ),
      ),
    );
    final boundary = find.byKey(const ValueKey('note-flow-status-semantics'));
    final identity = tester.getSemantics(boundary).id;
    update(() => label = 'Changes will save automatically');
    await tester.pumpAndSettle();
    expect(tester.getSemantics(boundary).id, identity);
    handle.dispose();
  });

  testWidgets('save status live region excludes the editable fields', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: Column(
            children: [
              NoteFlowPageHeader(
                breadcrumb: 'Notes',
                statusLabel: 'Changes will save automatically',
                statusDirty: true,
              ),
              TextField(decoration: InputDecoration(labelText: 'Content')),
            ],
          ),
        ),
      ),
    );
    for (
      SemanticsNode? node = tester.getSemantics(find.byType(TextField));
      node != null;
      node = node.parent
    ) {
      expect(node.getSemanticsData().flagsCollection.isLiveRegion, isFalse);
    }
    handle.dispose();
  });

  for (final iconOnly in [true, false]) {
    testWidgets(
      'disabled toolbar stays within its semantics boundary $iconOnly',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            home: Material(
              child: Column(
                children: [
                  NoteDetailActionBar(
                    isSaving: false,
                    isSummarizing: false,
                    canSave: false,
                    canSummarize: false,
                    onSave: null,
                    onSummarize: null,
                    onMore: null,
                    iconOnly: iconOnly,
                    saveLabel: 'Save',
                    summarizeLabel: 'Summarize',
                    moreLabel: 'More',
                    savingLabel: 'Saving',
                    summarizingLabel: 'Summarizing',
                  ),
                  const TextField(
                    decoration: InputDecoration(labelText: 'Title'),
                  ),
                ],
              ),
            ),
          ),
        );
        final node = tester.getSemantics(find.byType(TextField));
        for (
          SemanticsNode? ancestor = node;
          ancestor != null;
          ancestor = ancestor.parent
        ) {
          final data = ancestor.getSemanticsData();
          expect(data.flagsCollection.isEnabled, isNot(Tristate.isFalse));
        }
        expect(tester.takeException(), isNull);
        handle.dispose();
      },
    );
  }

  Future<void> panel(
    WidgetTester tester, {
    required bool protected,
    required bool shared,
    bool? locked,
  }) async {
    final now = DateTime.utc(2026, 10, 4);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteSecurityPanel(
            note: NoteDto(
              id: 'qa',
              ownerId: 'owner',
              title: '',
              content: '',
              createdAt: now,
              updatedAt: now,
              isProtected: protected,
              share: shared
                  ? NoteShareGrant(
                      note: NoteIdentity('owner', 'qa'),
                      recipientId: 'recipient',
                      role: NoteRole.editor,
                      sharedAt: now,
                      updatedAt: now,
                      accessRevision: 1,
                    )
                  : null,
            ),
            locked: locked ?? protected,
            busy: false,
            serverAvailable: true,
            canManage: false,
            retained: false,
            localFirst: true,
            onAction: (_) {},
            onBack: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('shared recipient has no owner protection controls', (
    tester,
  ) async {
    await panel(tester, protected: false, shared: true);
    expect(find.text('Enable protection'), findsNothing);
    await panel(tester, protected: true, shared: true);
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.text('Forgot password / OTP'), findsNothing);
    expect(find.text('Change password'), findsNothing);
    expect(find.text('Disable protection'), findsNothing);
  });
  testWidgets('locked owner retains OTP recovery', (tester) async {
    await panel(tester, protected: true, shared: false);
    expect(find.text('Forgot password / OTP'), findsOneWidget);
  });
  testWidgets('unprotected revoked note retains its unavailable and back UI', (
    tester,
  ) async {
    await panel(tester, protected: false, shared: true, locked: true);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Note unavailable'), findsOneWidget);
    expect(find.text('Enable protection'), findsNothing);
    expect(find.byKey(const ValueKey('note-security-enable')), findsNothing);
  });
}
