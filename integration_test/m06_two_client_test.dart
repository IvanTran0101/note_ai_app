import 'dart:convert';

import 'package:flutter/foundation.dart' hide Summary;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/sync/account_realtime_service.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/sync_coordinator_service.dart';
import 'package:note_ai_app/application/sync/sync_conflict_resolver.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/note_intelligence/summary.dart';
import 'package:note_ai_app/domain/notes/note_role.dart';
import 'package:note_ai_app/domain/notes/note_share_grant.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store.dart';
import 'package:note_ai_app/infrastructure/sync/http_remote_note_data_source.dart';
import 'package:note_ai_app/infrastructure/sync/appsync_revision_source.dart';
import 'package:note_ai_app/infrastructure/sync/realtime_socket.dart';
import 'package:note_ai_app/presentation/notes/notes_workspace_page.dart';
import 'package:note_ai_app/presentation/sync/sync_presentation_controller.dart';

const owner = 'm06-owner-20261002';
const editor = 'm06-editor-20261002';
const role = String.fromEnvironment('M06_CLIENT_ROLE', defaultValue: 'owner');
String get actor => role == 'owner' ? owner : editor;
String get host => kIsWeb ? '127.0.0.1' : '10.0.2.2';
String syntheticIdToken() =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': actor, 'token_use': 'id', 'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000}))).replaceAll('=', '')}.fixture';

final class ClientHarness {
  ClientHarness() {
    _wireSync();
    _wireApplication();
    _wireRealtime();
    _wirePresentation();
  }
  void _wireSync() {
    store = createLocalSyncStore(accountUserId: actor) as EncryptedSyncStore;
    remote = HttpRemoteNoteDataSource(
      baseUri: Uri.parse('http://$host:8786/'),
      tokenProvider: ({required forceRefresh}) async => actor,
    );
    coordinator = SyncCoordinatorService(
      accountUserId: actor,
      localStore: store,
      remote: remote,
    );
  }

  void _wireApplication() {
    session = CurrentUserSession()
      ..setIdentity(
        AuthIdentity(
          userId: actor,
          email: '$actor@example.invalid',
          isEmailVerified: true,
        ),
      );
    final repository = NoteRepository(
      currentAccountUserId: () => session.requiredUserId,
      localSyncStoreFactory: ({required accountUserId}) => store,
      generateMutationId: () => '$actor-${++ids}',
      now: DateTime.now,
    );
    app = NoteApplicationService(
      noteRepository: repository,
      currentUser: session,
      generateId: () => '$actor-new',
      now: DateTime.now,
      summarizeContent: (_) async => const Summary('Synthetic fixture summary'),
    );
  }

  void _wireRealtime() {
    realtime = AccountRealtimeService(
      source: AppSyncRevisionSource(
        httpEndpoint: Uri.parse('https://fixture.test/event'),
        socketEndpoint: Uri.parse('wss://fixture.test/event/realtime'),
        actorId: actor,
        tokenProvider: ({required forceRefresh}) async => syntheticIdToken(),
        socketFactory: (_, protocols) => ChannelRealtimeSocket(
          Uri.parse('ws://$host:8787/event/realtime'),
          protocols,
        ),
      ),
      isCurrentSession: () => session.userId == actor,
      synchronize: () async {
        await coordinator.syncNow();
      },
    );
  }

  void _wirePresentation() {
    presentation = SyncPresentationController(
      accountUserId: actor,
      localStore: store,
      coordinator: coordinator,
      conflictResolver: SyncConflictResolver(
        localSyncStore: store,
        generateNoteId: () => 'copy-${++ids}',
        generateMutationId: () => 'copy-m-${++ids}',
        now: DateTime.now,
      ),
    );
  }

  late final EncryptedSyncStore store;
  late final HttpRemoteNoteDataSource remote;
  late final SyncCoordinatorService coordinator;
  late final CurrentUserSession session;
  late final NoteApplicationService app;
  late final AccountRealtimeService realtime;
  late final SyncPresentationController presentation;
  int ids = 0;
  Future<http.Response> request(String path, [Map<String, Object?>? body]) =>
      body == null
      ? http.get(
          Uri.parse('http://$host:8786$path'),
          headers: {'authorization': 'Bearer $actor'},
        )
      : http.post(
          Uri.parse('http://$host:8786$path'),
          headers: {
            'authorization': 'Bearer $actor',
            'content-type': 'application/json',
          },
          body: jsonEncode(body),
        );
  Future<void> mark(String phase) async {
    expect((await request('/fixture/mark', {'phase': phase})).statusCode, 200);
  }

  Future<void> waitFlag(String who, String phase) => waitUntil(() async {
    final response = await request('/fixture/status');
    final data = jsonDecode(response.body) as Map;
    return data['$who-$phase'] == true;
  });
  Future<NoteDto> selected() async =>
      (role == 'owner' ? await app.listNotes() : await app.listSharedNotes())
          .single;
  Future<void> waitTitle(String title) => waitUntil(
    () async => (await store.read()).notes.any((n) => n.title == title),
  );
  Future<void> edit(String title) async {
    await app.saveEditorSnapshot(await selected(), title, 'Synthetic $title');
    final state = await store.read();
    expect(state.outbox, isNotEmpty);
    expect(
      state.notes.single.title,
      title,
    ); // Persisted locally before the HTTP push.
    if (role != 'owner') {
      expect(state.outbox.single.ownerId, owner);
      expect(state.outbox.single.accessRevision, 1);
    }
    await coordinator.syncNow();
    expect((await store.read()).outbox, isEmpty);
  }

  Future<void> permission(String action, int epoch) async {
    final response = await request(
      '/notes/fixture-note/shares?ownerId=$owner',
      {
        'requestId': '$action-$epoch',
        'action': action,
        'recipientId': editor,
        'expectedAccessRevision': epoch,
        if (action == 'role') 'role': 'viewer',
      },
    );
    expect(response.statusCode, 200);
  }

  Future<void> close() async {
    await realtime.dispose();
    presentation.dispose();
    await coordinator.dispose();
    remote.close();
    store.dispose();
  }
}

Future<void> waitUntil(Future<bool> Function() check) async {
  final until = DateTime.now().add(const Duration(minutes: 2));
  while (!await check()) {
    if (DateTime.now().isAfter(until)) {
      throw StateError('Two-client fixture deadline');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> ownerFlow(ClientHarness h) async {
  await h.waitFlag(editor, 'ready');
  await h.edit('Owner realtime');
  await h.waitFlag(editor, 'owner-seen');
  await h.waitTitle('Editor realtime');
  await h.mark('editor-seen');
  expect(
    (await h.request('/fixture/disconnect', {'actor': editor})).statusCode,
    200,
  );
  expect((await h.request('/fixture/lost-ack', {})).statusCode, 200);
  await h.edit('Reconnect catchup');
  await h.waitFlag(editor, 'reconnected');
  await h.permission('role', 1);
  await h.waitFlag(editor, 'viewer-denied');
  await h.permission('revoke', 2);
  await h.waitFlag(editor, 'revoked');
  final note = await h.selected();
  expect(note.title, 'Reconnect catchup');
  await h.mark('passed');
}

Future<void> editorFlow(ClientHarness h) async {
  await h.mark('ready');
  await h.waitTitle('Owner realtime');
  expect((await h.selected()).share!.role, NoteRole.editor);
  await h.mark('owner-seen');
  await h.edit('Editor realtime');
  await h.waitFlag(owner, 'editor-seen');
  await h.waitTitle('Reconnect catchup');
  await h.mark('reconnected');
  await waitUntil(
    () async =>
        (await h.store.read()).notes.single.share?.role == NoteRole.viewer,
  );
  final viewer = await h.selected();
  expect(h.app.capabilitiesFor(viewer).canEdit, false);
  await expectLater(
    h.app.saveEditorSnapshot(viewer, 'Unauthorized', 'Unauthorized'),
    throwsA(isA<Exception>()),
  );
  expect((await h.store.read()).outbox, isEmpty);
  await expectLater(
    h.remote.push(
      SyncMutation(
        mutationId: 'direct-viewer',
        noteId: 'fixture-note',
        ownerId: owner,
        accessRevision: 2,
        operation: SyncMutationOperation.update,
        baseRevision: viewer.contentRevision,
        payload: const SyncNotePayload(
          title: 'Unauthorized',
          content: 'Unauthorized',
        ),
      ),
    ),
    throwsA(
      isA<SyncFailure>().having((e) => e.code, 'code', SyncErrorCode.forbidden),
    ),
  );
  await h.mark('viewer-denied');
  await waitUntil(
    () async =>
        (await h.store.read()).notes.single.share?.status ==
        NoteShareStatus.revoked,
  );
  expect(await h.app.listSharedNotes(), isEmpty);
  final revoked = (await h.store.read()).notes.single;
  expect(revoked.contentAvailable, false);
  expect(revoked.title, isEmpty);
  expect(revoked.content, isEmpty);
  await h.mark('revoked');
  await h.mark('passed');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'two real $role client local-first edits, automatic cursor catch-up, reconnect and revoke',
    (tester) async {
      final h = ClientHarness();
      addTearDown(h.close);
      await tester.runAsync(() async {
        // Reset only this fixed synthetic fixture namespace, never real account data.
        await h.store.replace(LocalSyncState(accountUserId: actor));
        await h.coordinator.syncNow();
        h.realtime.start();
        await waitUntil(() async => (await h.store.read()).notes.isNotEmpty);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotesWorkspacePage(
              applicationService: h.app,
              syncController: h.presentation,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        if (role == 'owner') {
          await ownerFlow(h);
        } else {
          await editorFlow(h);
        }
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
