import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/domain/notes/note_role.dart';
import 'package:note_ai_app/domain/notes/note_share_grant.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';
import 'package:note_ai_app/presentation/notes/notes_workspace_page.dart';

import '../../sharing/m06_application_test.dart' as fixtures;

void main() {
  testWidgets('Shared With Me shows sharer, shared time, and permission', (
    tester,
  ) async {
    final h = fixtures.harness(role: NoteRole.viewer);
    final at = DateTime.utc(2026, 10, 2);
    final share = NoteShareGrant(
      note: fixtures.grant().note,
      recipientId: 'actor',
      role: NoteRole.viewer,
      sharedAt: at,
      updatedAt: at,
      accessRevision: 1,
      sharerLabel: 'Note owner',
    );
    await h.store.replace(
      LocalSyncState(
        accountUserId: 'actor',
        notes: [fixtures.owned(), fixtures.shared(share: share)],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NotesWorkspacePage(
          controller: NoteApplicationServiceController(h.app),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shared-notes-tab')));
    await tester.pumpAndSettle();

    final timestamp = at.toLocal().toIso8601String().split('.').first;
    expect(find.textContaining('Note owner'), findsOneWidget);
    expect(find.textContaining(timestamp), findsOneWidget);
    expect(find.textContaining('Viewer'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
