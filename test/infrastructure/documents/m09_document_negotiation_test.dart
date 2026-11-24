import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/sync_coordinator_service.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/sync_cursor.dart';
import 'package:note_ai_app/infrastructure/sync/http_remote_note_data_source.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_state_codec.dart';

import '../notes/note_repository_test_support.dart' show FakeLocalSyncStore;
import 'm09_storage_fixtures.dart' as fixture;
import 'm09_document_wire_test.dart' show wireNote, wirePage;

HttpRemoteNoteDataSource remote(MockClient client) => HttpRemoteNoteDataSource(
  baseUri: Uri.parse('https://fixture.invalid'),
  labelsEnabled: true,
  documentsEnabled: true,
  tokenProvider: ({required forceRefresh}) async => 'synthetic',
  client: client,
);
http.Response response(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

void main() {
  test(
    'V3 probe is separate from opaque pull cursor; downgrade is not fabricated',
    () async {
      final requests = <Uri>[];
      final adapter = remote(
        MockClient((r) async {
          requests.add(r.url);
          return response(wirePage([]));
        }),
      );
      expect(await adapter.negotiateWireVersion(), 3);
      expect(
        await adapter.pull(cursor: 'opaque+cursor/=', limit: 4),
        isNotNull,
      );
      expect(requests.first.queryParameters, {'limit': '1'});
      expect(requests.last.path, '/sync/v3/changes');
      expect(requests.last.queryParameters['cursor'], 'opaque+cursor/=');
    },
  );

  test('older backend retains rich outbox, continues V2 pull and upgrades exact retry later', () async {
    var upgraded = false;
    final paths = <String>[];
    final posts = <Map>[];
    final adapter = remote(
      MockClient((r) async {
        paths.add(r.url.path);
        if (r.url.path == '/sync/v3/changes') {
          return upgraded
              ? response(wirePage([]))
              : response({'code': 'NOT_FOUND'}, 404);
        }
        if (r.method == 'POST') {
          posts.add(jsonDecode(r.body) as Map);
          return response({
            'wireVersion': 3,
            'documentCapability': 'basicBlocksV1',
            'status': 'applied',
            'mutationId': 'attempt',
            'note': wireNote(),
          });
        }
        return response({
          'wireVersion': 2,
          'items': [],
          'nextCursor': 'cursor',
          'hasMore': false,
        });
      }),
    );
    final store = FakeLocalSyncStore(
      accountUserId: 'owner',
      initial: fixture.state(queued: true, retryCount: 2),
    );
    final coordinator = SyncCoordinatorService(
      accountUserId: 'owner',
      localStore: store,
      remote: adapter,
      labelsEnabled: true,
      delay: (_) async {},
    );
    await expectLater(
      coordinator.syncNow(),
      throwsA(
        isA<SyncFailure>().having(
          (e) => e.code,
          'code',
          SyncErrorCode.documentRequiresUpgrade,
        ),
      ),
    );
    var state = await store.read();
    expect(state.notes.single.document, fixture.doc());
    expect(state.outbox.single.blocked, true);
    expect(
      state.outbox.single.lastError,
      SyncErrorCode.documentRequiresUpgrade,
    );
    expect(state.outbox.single.mutationId, 'attempt');
    expect(state.syncWireVersion, 2);
    expect(posts, isEmpty);
    expect(paths, contains('/sync/v2/changes'));
    upgraded = true;
    await coordinator.syncNow();
    state = await store.read();
    expect(state.outbox, isEmpty);
    expect(state.notes.single.document, fixture.doc());
    expect(posts.single['mutationId'], 'attempt');
    expect(
      (posts.single['payload'] as Map)['content'],
      fixture.doc().plainText,
    );
    expect(state.syncWireVersion, 3);
    expect(
      LocalSyncStateCodec.decode(LocalSyncStateCodec.encode(state))
          .syncWireVersion,
      3,
    );
    await coordinator.dispose();
  });

  test(
    'new capability backfills old cursor once, then resumes new typed cursor',
    () async {
      final cursors = <String?>[];
      final adapter = remote(
        MockClient((r) async {
          final q = r.url.queryParameters;
          if (q['limit'] == '1') return response(wirePage([]));
          cursors.add(q['cursor']);
          return response({...wirePage([]), 'nextCursor': 'typed-cursor'});
        }),
      );
      final store = FakeLocalSyncStore(
        accountUserId: 'owner',
        initial: LocalSyncState(
          accountUserId: 'owner',
          cursor: const SyncCursor('old-cursor'),
          syncWireVersion: 2,
        ),
      );
      final coordinator = SyncCoordinatorService(
        accountUserId: 'owner',
        localStore: store,
        remote: adapter,
        labelsEnabled: true,
      );
      await coordinator.syncNow();
      await coordinator.syncNow();
      expect(cursors, [null, 'typed-cursor']);
      expect((await store.read()).cursor!.value, 'typed-cursor');
      await coordinator.dispose();
    },
  );

  test(
    'malformed successful capability refuses; no request downgrades rich bytes',
    () async {
      final paths = <String>[];
      final adapter = remote(
        MockClient((r) async {
          paths.add(r.url.path);
          return response({
            'wireVersion': 3,
            'items': [],
            'documentCapability': 'unknown',
          });
        }),
      );
      await expectLater(
        adapter.push(fixture.pending().toMutation()),
        throwsA(isA<SyncFailure>()),
      );
      expect(paths, ['/sync/v3/changes']);
    },
  );
}
