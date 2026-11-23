import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_dto.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_role.dart';
import 'package:note_ai_app/domain/notes/note_share_grant.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_localizations.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_note_card.dart';
import 'package:note_ai_app/presentation/notes/animated_note_list.dart';

void main() {
  for (final layout in DashboardNoteCardLayout.values) {
    testWidgets(
      'NOTE-FR-12/NFR-05: shared status is announced in ${layout.name}',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final now = DateTime.utc(2026, 11, 10);
        final note = NoteDto(
          id: 'received-note',
          ownerId: 'owner',
          title: 'Meeting notes',
          content: 'Agenda',
          createdAt: now,
          updatedAt: now,
          share: NoteShareGrant(
            note: NoteIdentity('owner', 'received-note'),
            recipientId: 'recipient',
            role: NoteRole.viewer,
            sharedAt: now,
            updatedAt: now,
            accessRevision: 1,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [DashboardCopy.delegate],
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: SizedBox(
                    width: 320,
                    child: DashboardNoteCard(
                      note: note,
                      copy: DashboardCopy.of(context),
                      layout: layout,
                      showPreview: false,
                      onTap: (_) {},
                      onTogglePin: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsLabel(RegExp('shared', caseSensitive: false)),
          findsWidgets,
          reason:
              'The received-note card must announce sharing independently '
              'of title, preview, color, or a disabled pin action.',
        );
        semantics.dispose();
      },
    );
  }

  testWidgets('NOTE-FR-12/NFR-05: workspace announces pinned status', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final now = DateTime.utc(2026, 11, 10);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: AnimatedNoteList(
            notes: [
              NoteDto(
                id: 'pinned-note',
                ownerId: 'owner',
                title: 'Meeting notes',
                content: 'Agenda',
                createdAt: now,
                updatedAt: now,
                pinnedAt: now,
              ),
            ],
            selectedNoteId: null,
            actionBusy: false,
            onSelectNote: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('pinned', caseSensitive: false)),
      findsWidgets,
      reason: 'Sorting alone does not identify a pinned note.',
    );
    semantics.dispose();
  });
}
