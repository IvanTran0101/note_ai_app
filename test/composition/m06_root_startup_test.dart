import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_ai_app/application/auth/auth_models.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/sync/revision_source.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/infrastructure/configuration/note_connection.dart';
import 'package:note_ai_app/main.dart';
import 'package:note_ai_app/presentation/auth/controllers/auth_controller.dart';
import 'package:note_ai_app/presentation/notes/notes_workspace_page.dart';
import 'package:note_ai_app/presentation/common/note_flow_primitives.dart';
import 'package:note_ai_app/presentation/workspace/workspace_shell.dart';

import '../infrastructure/notes/note_repository_test_support.dart';

final class _SilentSource implements IRevisionSource {
  @override
  Stream<RevisionNotice> get notices => const Stream.empty();
  @override
  void start() {}
  @override
  void reconnect() {}
  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('open settings follows a language change without reopening', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1363, 936)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = CurrentUserSession()
      ..setIdentity(
        AuthIdentity(
          userId: 'settings-qa-owner',
          email: 'owner@example.invalid',
          isEmailVerified: true,
        ),
      );
    final auth = AuthController(
      authenticationAppService: null,
      initialUser: AuthUserDto.fromIdentity(session.identity!),
    );
    final store = FakeLocalSyncStore(accountUserId: session.requiredUserId);
    final client = MockClient(
      (_) async =>
          http.Response('{"items":[],"nextCursor":null,"hasMore":false}', 200),
    );
    try {
      await tester.pumpWidget(
        NoteFlowApp(
          authController: auth,
          currentUserSession: session,
          localSyncStoreFactory: ({required accountUserId}) => store,
          connection: NoteConnection(
            baseUri: Uri.parse('https://startup.test'),
            tokenProvider: ({required forceRefresh}) async => null,
            client: client,
            revisionSourceFor: (_) => _SilentSource(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final shell = tester.state<WorkspaceShellState>(
        find.byType(WorkspaceShell),
      );
      final destination = shell.destination;
      await tester.tap(find.byKey(WorkspaceShell.settingsKey));
      await tester.pumpAndSettle();
      expect(find.text('Appearance and language'), findsOneWidget);
      await tester.tap(
        find
            .byWidgetPredicate(
              (widget) => widget is DropdownButtonFormField<Object?>,
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vietnamese').last);
      await tester.pumpAndSettle();
      expect(find.text('Giao diện và ngôn ngữ'), findsOneWidget);
      expect(find.text('Ngôn ngữ'), findsOneWidget);
      expect(find.text('Đăng xuất'), findsOneWidget);
      expect(shell.destination, destination);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      client.close();
    }
  });

  testWidgets('long sync/conflict status fits a narrow editor header', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            child: NoteFlowPageHeader(
              breadcrumb: 'Notes',
              statusLabel: 'This note changed on another device. Your draft stays here; choose cloud or explicitly save local against the new version.',
              statusError: true,
              onBack: () {},
              actions: [
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.more_horiz),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('restored identity initializes sync before Notes mounts', (
    tester,
  ) async {
    final session = CurrentUserSession()
      ..setIdentity(
        AuthIdentity(
          userId: 'm06-dev-owner',
          email: 'owner@example.invalid',
          isEmailVerified: true,
        ),
      );
    final auth = AuthController(
      authenticationAppService: null,
      initialUser: AuthUserDto.fromIdentity(session.identity!),
    );
    final store = FakeLocalSyncStore(accountUserId: session.requiredUserId);
    final client = MockClient(
      (_) async =>
          http.Response('{"items":[],"nextCursor":null,"hasMore":false}', 200),
    );
    await tester.pumpWidget(
      NoteFlowApp(
        authController: auth,
        currentUserSession: session,
        localSyncStoreFactory: ({required accountUserId}) => store,
        connection: NoteConnection(
          baseUri: Uri.parse('https://startup.test'),
          tokenProvider: ({required forceRefresh}) async => null,
          client: client,
          revisionSourceFor: (_) => _SilentSource(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.byType(NotesWorkspacePage, skipOffstage: false),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    client.close();
  });
}
