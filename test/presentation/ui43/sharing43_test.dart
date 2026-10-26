import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_role.dart';
import 'package:note_ai_app/domain/notes/note_share_grant.dart';
import 'package:note_ai_app/presentation/notes/notes_theme_tokens.dart';
import 'package:note_ai_app/presentation/notes/share_management_dialog.dart';
import 'package:note_ai_app/presentation/notes/share_management_surface.dart';
import 'package:note_ai_app/presentation/notes/sharing_localizations.dart';

void main() {
  testWidgets('native share sheet remains scrollable with IME and large text', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(320, 640)
      ..devicePixelRatio = 1
      ..viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [NoteFlowUiTokens.light()]),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            final tokens = NoteFlowUiTokens.of(context);
            return Scaffold(
              body: ShareManagementSurface(
                title: 'Manage sharing',
                closeLabel: 'Close',
                onClose: () {},
                tokens: tokens,
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ShareInviteField(
                      controller: controller,
                      enabled: true,
                      label: 'Verified account email',
                      compact: true,
                      tokens: tokens,
                    ),
                    const SizedBox(height: 8),
                    ShareErrorNotice(
                      message:
                          'Connection lost. Retry to confirm the same request.',
                      tokens: tokens,
                    ),
                    const SizedBox(height: 8),
                    ShareRecipientRow(
                      share: _share(
                        'long.identity.with.multiple.sections.and.a.long.domain@example.test',
                      ),
                      copy: SharingCopy(context),
                      compact: true,
                      enabled: true,
                      onChangeRole: () {},
                      onRevoke: () {},
                      onReactivate: () {},
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.byKey(const ValueKey('share-error')), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('share-recipient-email')))
          .height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets(
    'wide recipient permission control exposes current roles and revoke',
    (tester) async {
      const recipientId = 'member@example.test';
      var changedRole = 0;
      var revoked = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [NoteFlowUiTokens.light()]),
          home: Builder(
            builder: (context) => Scaffold(
              body: SizedBox(
                width: 456,
                child: ShareRecipientRow(
                  share: _share(recipientId),
                  copy: SharingCopy(context),
                  compact: false,
                  enabled: true,
                  onChangeRole: () => changedRole++,
                  onRevoke: () => revoked++,
                  onReactivate: () {},
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(recipientId), findsOneWidget);
      expect(
        find.byKey(const ValueKey('share-recipient-permission')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('share-recipient-permission')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Viewer'), findsOneWidget);
      expect(find.text('Revoke'), findsOneWidget);

      await tester.tap(find.text('Viewer'));
      await tester.pumpAndSettle();
      expect(changedRole, 1);

      await tester.tap(
        find.byKey(const ValueKey('share-recipient-permission')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();
      expect(revoked, 1);
    },
  );
}

NoteShareGrant _share(String recipientId) {
  final now = DateTime.utc(2026, 10, 26, 10);
  return NoteShareGrant(
    note: NoteIdentity('owner-1', 'note-1'),
    recipientId: recipientId,
    role: NoteRole.editor,
    sharedAt: now,
    updatedAt: now,
    accessRevision: 1,
  );
}
