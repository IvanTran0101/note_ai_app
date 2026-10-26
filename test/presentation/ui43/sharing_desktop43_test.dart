import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_sharing_app_service.dart';
import 'package:note_ai_app/application/notes/sharing_gateway.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_share_grant.dart';
import 'package:note_ai_app/presentation/notes/share_management_dialog.dart';

import '../../sharing/m06_application_test.dart' as fixtures;

void main() {
  for (final networkError in [false, true]) {
    testWidgets(
      'desktop Share lays out responsive invite and error=$networkError',
      (tester) async {
        tester.view
          ..physicalSize = const Size(1280, 740)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final fixture = fixtures.harness();
        final service = NoteSharingAppService(
          notes: fixture.app,
          gateway: _LayoutGateway(networkError),
          generateRequestId: () => 'layout-only',
          sessionGeneration: () => fixture.session.sessionGeneration,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => ShareManagementDialog(
                      service: service,
                      identity: NoteIdentity('actor', 'same'),
                      sessionEvents: const Stream.empty(),
                      isCurrent: () => true,
                    ),
                  ),
                  child: const Text('Open share'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open share'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(
          find.byKey(const ValueKey('share-recipient-submit')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('share-recipient-role')),
          findsOneWidget,
        );
        if (networkError) {
          expect(find.byKey(const ValueKey('share-error')), findsOneWidget);
          expect(find.byKey(const ValueKey('share-retry')), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(ShareManagementDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}

final class _LayoutGateway implements ISharingGateway {
  _LayoutGateway(this.networkError);
  final bool networkError;
  @override
  Future<List<NoteShareGrant>> list(NoteIdentity note) async {
    if (networkError) throw const ShareFailure(ShareFailureCode.network);
    return const [];
  }

  @override
  Future<NoteShareGrant> apply(NoteIdentity note, ShareCommand command) =>
      throw StateError('A layout test must not submit an invitation.');
}
