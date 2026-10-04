import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_dto.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_role.dart';
import 'package:note_ai_app/domain/notes/note_share_grant.dart';
import 'package:note_ai_app/presentation/notes/note_security_panel.dart';

void main() {
  testWidgets(
    'revoked unprotected share describes access drafts, not old passwords',
    (tester) async {
      final time = DateTime.utc(2026, 10, 5);
      final note = NoteDto(
        id: 'n',
        ownerId: 'owner',
        title: '',
        content: '',
        createdAt: time,
        updatedAt: time,
        contentAvailable: false,
        share: NoteShareGrant(
          note: NoteIdentity('owner', 'n'),
          recipientId: 'recipient',
          role: NoteRole.editor,
          sharedAt: time,
          updatedAt: time,
          revokedAt: time,
          status: NoteShareStatus.revoked,
          accessRevision: 2,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteSecurityPanel(
              note: note,
              locked: true,
              busy: false,
              serverAvailable: true,
              canManage: false,
              retained: true,
              onAction: (_) {},
            ),
          ),
        ),
      );
      expect(find.textContaining('earlier access'), findsOneWidget);
      expect(find.textContaining('old password'), findsNothing);
      expect(find.text('Enable protection'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
