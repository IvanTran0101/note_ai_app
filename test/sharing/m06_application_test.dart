import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/notes/note_sharing_app_service.dart';
import 'package:note_ai_app/application/notes/sharing_gateway.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/sync_metadata_projection.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/note_intelligence/summary.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_role.dart';
import 'package:note_ai_app/domain/notes/note_share_grant.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';
import 'package:note_ai_app/infrastructure/notes/http_share_gateway.dart';
import 'package:note_ai_app/infrastructure/sync/sync_http_mapper.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';
import 'package:note_ai_app/presentation/notes/notes_workspace_page.dart';
import 'package:note_ai_app/presentation/notes/share_management_dialog.dart';

import '../infrastructure/notes/note_repository_test_support.dart';
import '../presentation/editor/rich_editor_test_support.dart';

final at = DateTime.utc(2026, 10, 2);
NoteShareGrant grant({
  NoteRole role = NoteRole.editor,
  int epoch = 1,
  bool active = true,
}) => NoteShareGrant(
  note: NoteIdentity('owner', 'same'),
  recipientId: 'actor',
  role: role,
  sharedAt: at,
  updatedAt: at,
  accessRevision: epoch,
  status: active ? NoteShareStatus.active : NoteShareStatus.revoked,
  revokedAt: active ? null : at,
);
LocalNoteState shared({NoteShareGrant? share, bool available = true}) =>
    LocalNoteState(
      id: 'same',
      ownerId: 'owner',
      share: share ?? grant(),
      title: available ? 'Shared title' : '',
      content: available ? 'Shared body' : '',
      createdAt: at,
      updatedAt: at,
      serverRevision: 7,
      contentAvailable: available,
    );
LocalNoteState owned({int revision = 3}) => LocalNoteState(
  id: 'same',
  ownerId: 'actor',
  title: 'Owned title',
  content: 'Owned body',
  createdAt: at,
  updatedAt: at,
  serverRevision: revision,
);

({
  NoteApplicationService app,
  NoteRepository repo,
  FakeLocalSyncStore store,
  CurrentUserSession session,
})
harness({NoteRole role = NoteRole.editor, int ownedRevision = 3}) {
  final session = CurrentUserSession()
    ..setIdentity(
      AuthIdentity(
        userId: 'actor',
        email: 'actor@example.test',
        isEmailVerified: true,
      ),
    );
  final store = FakeLocalSyncStore(
    accountUserId: 'actor',
    initial: LocalSyncState(
      accountUserId: 'actor',
      notes: [
        owned(revision: ownedRevision),
        shared(share: grant(role: role)),
      ],
    ),
  );
  var id = 0;
  final repo = NoteRepository(
    currentAccountUserId: () => session.requiredUserId,
    localSyncStoreFactory: ({required accountUserId}) => store,
    generateMutationId: () => 'mutation-${++id}',
    now: () => at,
  );
  final app = NoteApplicationService(
    noteRepository: repo,
    currentUser: session,
    generateId: () => 'new',
    now: () => at,
    summarizeContent: (_) async => const Summary('synthetic'),
  );
  return (app: app, repo: repo, store: store, session: session);
}

void main() {
  testWidgets(
    'management UI validates email and retries identical uncertain command',
    (tester) async {
      final h = harness();
      final gateway = FakeSharingGateway()..failFirst = true;
      var request = 0;
      final service = NoteSharingAppService(
        notes: h.app,
        gateway: gateway,
        generateRequestId: () => 'request-${++request}',
        sessionGeneration: () => h.session.sessionGeneration,
      );
      tester.testTextInput.register();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShareManagementDialog(
              service: service,
              identity: NoteIdentity('actor', 'same'),
              sessionEvents: const Stream<void>.empty(),
              isCurrent: () => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('share-recipient-email')),
        'invalid',
      );
      await tester.tap(find.byKey(const ValueKey('share-recipient-submit')));
      await tester.pumpAndSettle();
      expect(gateway.commands, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('share-recipient-email')),
        'recipient@example.test',
      );
      await tester.tap(find.byKey(const ValueKey('share-recipient-submit')));
      await tester.pumpAndSettle();
      expect(gateway.commands.length, 1);
      expect(find.text('recipient-verified'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('share-retry')));
      await tester.pumpAndSettle();
      expect(gateway.commands.length, 2);
      expect(identical(gateway.commands.first, gateway.commands.last), true);
      expect(find.text('recipient-verified'), findsOneWidget);
      expect(gateway.commands.last.role, NoteRole.viewer);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'shared list preserves pair and owned list excludes received notes',
    () async {
      final h = harness();
      expect((await h.app.listNotes()).single.ownerId, 'actor');
      final received = (await h.app.listSharedNotes()).single;
      expect(received.identity, grant().note);
      expect(received.reference, isNot('same'));
      expect((await h.app.readNote('same')).ownerId, 'actor');
      expect((await h.app.readNote(received.reference)).ownerId, 'owner');
    },
  );
  test(
    'editor edits persist locally with canonical owner and original epoch',
    () async {
      final h = harness();
      final note = (await h.app.listSharedNotes()).single;
      await h.app.replaceContent(
        noteId: note.reference,
        content: 'offline edit',
      );
      expect(h.store.state.notes.first.content, 'Owned body');
      expect(h.store.state.notes.last.content, 'offline edit');
      final pending = h.store.state.outbox.single;
      expect(pending.ownerId, 'owner');
      expect(pending.accessRevision, 1);
      expect(pending.baseRevision, 7);
      expect(encodeSyncMutation(pending.mutation)['ownerId'], 'owner');
      await h.app.renameNote(noteId: note.reference, title: 'offline title');
      expect(h.store.state.outbox.single.mutationId, pending.mutationId);
    },
  );
  test('viewer cannot edit, delete, export or administer', () async {
    final h = harness(role: NoteRole.viewer);
    final note = (await h.app.listSharedNotes()).single;
    final caps = h.app.capabilitiesFor(note);
    expect(caps.canRead, true);
    expect(caps.canSummarize, true);
    expect(
      caps.canEdit || caps.canDelete || caps.canManage || caps.canExport,
      false,
    );
    await expectLater(
      h.app.replaceContent(noteId: note.reference, content: 'bypass'),
      throwsA(anything),
    );
    await expectLater(h.app.deleteNote(note.reference), throwsA(anything));
    expect(h.store.state.outbox, isEmpty);
  });
  test(
    'repository refuses stale editor snapshot after role downgrade',
    () async {
      final h = harness();
      final old = (await h.repo.findSharedWith('actor')).single;
      await h.store.replace(
        LocalSyncState(
          accountUserId: 'actor',
          notes: [
            owned(),
            shared(share: grant(role: NoteRole.viewer, epoch: 2)),
          ],
        ),
      );
      old.replaceContent('stale bypass', at);
      await expectLater(h.repo.save(old), throwsA(anything));
      expect(h.store.state.outbox, isEmpty);
    },
  );
  test(
    'deleting local owned same-id draft preserves the received note',
    () async {
      final h = harness(ownedRevision: 0);
      await h.app.deleteNote('same');
      expect(h.store.state.notes.single.ownerId, 'owner');
      expect(h.store.state.outbox, isEmpty);
    },
  );
  test(
    'metadata redaction preserves foreign identity and pending access epoch',
    () async {
      final h = harness();
      final ref = grant().note.referenceFor('actor');
      await h.app.replaceContent(noteId: ref, content: 'queued');
      final state = LocalSyncState(
        accountUserId: 'actor',
        notes: [owned(), shared(available: false)],
        outbox: h.store.state.outbox,
      );
      final projection = SyncMetadataProjection.state(state);
      expect(projection.notes.first.content, 'Owned body');
      expect(projection.notes.last.share, grant());
      expect(projection.outbox.single.ownerId, 'owner');
      expect(projection.outbox.single.accessRevision, 1);
      expect(projection.outbox.single.payload!.content, '');
    },
  );
  test('owner administration waits for saved server revision', () async {
    final h = harness(ownedRevision: 0);
    final gateway = FakeSharingGateway();
    final service = NoteSharingAppService(
      notes: h.app,
      gateway: gateway,
      generateRequestId: () => 'request',
      sessionGeneration: () => h.session.sessionGeneration,
    );
    await expectLater(
      service.list(NoteIdentity('actor', 'same')),
      throwsA(
        isA<ShareFailure>().having(
          (e) => e.code,
          'code',
          ShareFailureCode.pendingSync,
        ),
      ),
    );
    expect(gateway.calls, 0);
  });
  test('pending sharing ACK cannot cross account session', () async {
    final h = harness();
    final gateway = FakeSharingGateway()
      ..gate = Completer<List<NoteShareGrant>>();
    final service = NoteSharingAppService(
      notes: h.app,
      gateway: gateway,
      generateRequestId: () => 'request',
      sessionGeneration: () => h.session.sessionGeneration,
    );
    final result = service.list(NoteIdentity('actor', 'same'));
    await Future<void>.delayed(Duration.zero);
    h.session.clear();
    gateway.gate!.complete([]);
    await expectLater(result, throwsA(isA<ShareFailure>()));
  });
  test('share gateway safely rejects malformed metadata', () async {
    final token =
        'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'actor'}))).replaceAll('=', '')}.signature';
    final gateway = HttpShareGateway(
      baseUri: Uri.parse('https://example.test/'),
      actorId: 'actor',
      tokenProvider: ({required forceRefresh}) async => token,
      isCurrent: () => true,
      grantHeader: (_) async => null,
      client: MockClient(
        (_) async => http.Response('{"shares":[{"password":"private"}]}', 200),
      ),
    );
    await expectLater(
      gateway.list(NoteIdentity('actor', 'same')),
      throwsA(isA<ShareFailure>()),
    );
  });
  testWidgets(
    'Shared with me section renders role and opens canonical same-id note',
    (tester) async {
      final h = harness(role: NoteRole.viewer);
      final controller = NoteApplicationServiceController(h.app);
      await tester.pumpWidget(
        MaterialApp(home: NotesWorkspacePage(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Owned title'), findsOneWidget);
      expect(find.text('Shared title'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('shared-notes-tab')));
      await tester.pumpAndSettle();
      expect(find.text('Shared title'), findsOneWidget);
      expect(find.textContaining('Viewer'), findsOneWidget);
      expect(find.byKey(const ValueKey('new-note')), findsNothing);
      await tester.tap(find.text('Shared title'));
      await tester.pumpAndSettle();
      final editor = visibleRichEditor(tester);
      expect(editor.plainText, 'Shared body');
      expect(editor.editable, false);
      expect(editor.capture(), null);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

final class FakeSharingGateway implements ISharingGateway {
  int calls = 0;
  bool failFirst = false;
  final commands = <ShareCommand>[];
  Completer<List<NoteShareGrant>>? gate;
  @override
  Future<List<NoteShareGrant>> list(NoteIdentity note) async {
    calls++;
    return gate?.future ?? [];
  }

  @override
  Future<NoteShareGrant> apply(NoteIdentity note, ShareCommand command) async {
    calls++;
    commands.add(command);
    if (failFirst && commands.length == 1) {
      throw const ShareFailure(ShareFailureCode.network);
    }
    return NoteShareGrant(
      note: note,
      recipientId: 'recipient-verified',
      role: command.role ?? NoteRole.viewer,
      sharedAt: at,
      updatedAt: at,
      accessRevision: command.expectedAccessRevision + 1,
    );
  }
}
