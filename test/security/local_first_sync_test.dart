import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/local_protection_queue.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/protection_sync_change.dart';
import 'package:note_ai_app/application/sync/sync_coordinator_service.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_conflict_resolver.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/sync/http_remote_note_data_source.dart';
import 'package:note_ai_app/infrastructure/sync/protection_sync_codec.dart';

import '../application/sync/sync_coordinator_service_test.dart'
    show MemoryStore;
import 'local_first_scenarios.dart';
import 'security_fixtures.dart';

const representation =
    'pbkdf2-sha256-v1\$AAAAAAAAAAAAAAAAAAAAAA==\$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
final protection = NoteProtection(enabled: true, revision: 1);
ProtectionSyncChange change() => ProtectionSyncChange(
  before: const NoteProtection.unprotected(),
  after: protection,
  verifier: representation,
);
LocalSyncState sealed(String account) => LocalSyncState(
  accountUserId: account,
  notes: [
    LocalNoteState(
      id: 'alpha',
      ownerId: account,
      title: privateTitle,
      content: privateBody,
      createdAt: fixtureTime,
      updatedAt: fixtureTime,
      protection: protection,
    ),
  ],
  outbox: unsynced(account).outbox,
);

Map<String, Object?> ack(String id) => {
  'status': 'applied',
  'mutationId': id,
  'note': {
    'id': 'alpha',
    'title': '',
    'content': '',
    'revision': 1,
    'createdAt': fixtureTime.toIso8601String(),
    'serverUpdatedAt': fixtureTime.toIso8601String(),
    'deletedAt': null,
    'protected': true,
    'protectionRevision': 1,
    'contentAvailable': false,
  },
};

void main() {
  test('strict protection codec rejects raw/password/unknown fields and round trips representation', () {
    expect(
      ProtectionSyncCodec.decode(ProtectionSyncCodec.encode(change())),
      change(),
    );
    expect(
      () => ProtectionSyncCodec.encode(
        ProtectionSyncChange(
          before: const NoteProtection.unprotected(),
          after: protection,
          verifier: securityPassword,
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => ProtectionSyncCodec.decode({
        ...ProtectionSyncCodec.encode(change()),
        'password': securityPassword,
      }),
      throwsException,
    );
    expect(
      () => SyncMutation(
        mutationId: 'id',
        noteId: 'alpha',
        operation: SyncMutationOperation.delete,
        baseRevision: 0,
        protectionChange: change(),
      ),
      throwsArgumentError,
    );
    expect(change().toString(), isNot(contains(representation)));
  });

  test('coalescing preserves unsent identity; attempted predecessor stays byte-for-byte frozen', () {
    final original = unsynced('owner');
    final queued = LocalProtectionQueue.apply(
      original,
      original.notes.first,
      sealed('owner'),
      change(),
      'fresh-id',
      fixtureTime,
    );
    expect(queued.outbox.single.mutationId, 'local-create');
    final old = original.outbox.single;
    final attempted = PendingMutation(
      mutationId: old.mutationId,
      noteId: old.noteId,
      operation: old.operation,
      baseRevision: old.baseRevision,
      payload: old.payload,
      createdAt: old.createdAt,
      retryCount: 3,
    );
    final state = LocalSyncState(
      accountUserId: 'owner',
      notes: original.notes,
      outbox: [attempted],
    );
    final staged = LocalSyncState(
      accountUserId: 'owner',
      notes: sealed('owner').notes,
      outbox: [attempted],
    );
    final result = LocalProtectionQueue.apply(
      state,
      state.notes.first,
      staged,
      change(),
      'fresh-id',
      fixtureTime,
    );
    expect(result.outbox.first, attempted);
    expect(result.outbox.last.mutationId, 'fresh-id');
    expect(result.outbox.last.baseRevision, 1);
    expect(result.outbox.last.protectionChange, change());
  });

  test('existing sync engine pushes new protection through dedicated path and ACK preserves local body', () async {
    final initial = unsynced('owner');
    final store = MemoryStore(
      LocalProtectionQueue.apply(
        initial,
        initial.notes.first,
        sealed('owner'),
        change(),
        'id',
        fixtureTime,
      ),
    );
    final requests = <http.Request>[];
    final remote = HttpRemoteNoteDataSource(
      baseUri: Uri.parse('https://synthetic.invalid/'),
      tokenProvider: ({required forceRefresh}) async => 'synthetic-token',
      client: MockClient((r) async {
        requests.add(r);
        if (r.method == 'GET') {
          return http.Response(
            jsonEncode({'items': [], 'hasMore': false, 'nextCursor': null}),
            200,
          );
        }
        expect(r.url.path, '/sync/protected-mutations');
        expect(
          jsonDecode(r.body)['protectionChange']['verifier'],
          representation,
        );
        expect(r.body, isNot(contains(securityPassword)));
        return http.Response(jsonEncode(ack('local-create')), 200);
      }),
    );
    final coordinator = SyncCoordinatorService(
      accountUserId: 'owner',
      localStore: store,
      remote: remote,
    );
    addTearDown(coordinator.dispose);
    final report = await coordinator.syncNow();
    expect(report.applied, 1);
    expect(store.state.outbox, isEmpty);
    expect(store.state.notes.single.content, privateBody);
    expect(store.state.notes.single.protection, protection);
    expect(requests.where((r) => r.method == 'POST').length, 1);
  });

  test('unknown delivery uses only read-only inspection; conflict use-local retains protection descriptor', () async {
    final old = unsynced('owner').outbox.single;
    final attempted = PendingMutation(
      mutationId: old.mutationId,
      noteId: old.noteId,
      operation: old.operation,
      baseRevision: old.baseRevision,
      payload: old.payload,
      createdAt: old.createdAt,
      retryCount: 1,
    );
    final initial = LocalSyncState(
      accountUserId: 'owner',
      notes: unsynced('owner').notes,
      outbox: [attempted],
    );
    final staged = LocalSyncState(
      accountUserId: 'owner',
      notes: sealed('owner').notes,
      outbox: [attempted],
    );
    final store = MemoryStore(
      LocalProtectionQueue.apply(
        initial,
        initial.notes.first,
        staged,
        change(),
        'protect-id',
        fixtureTime,
      ),
    );
    final paths = <String>[];
    final remote = HttpRemoteNoteDataSource(
      baseUri: Uri.parse('https://synthetic.invalid/'),
      tokenProvider: ({required forceRefresh}) async => 'synthetic-token',
      mutationGrant: (_) async =>
          throw const NoteSecurityFailure(NoteSecurityFailureCode.pendingSync),
      client: MockClient((r) async {
        paths.add(r.url.path);
        if (r.method == 'GET') {
          return http.Response(
            jsonEncode({'items': [], 'hasMore': false, 'nextCursor': null}),
            200,
          );
        }
        expect(r.url.path, '/sync/protection-predecessor');
        return http.Response(
          jsonEncode({
            'code': 'REVISION_CONFLICT',
            'mutationId': old.mutationId,
            'remoteNote': null,
            'retryable': false,
          }),
          409,
        );
      }),
    );
    final coordinator = SyncCoordinatorService(
      accountUserId: 'owner',
      localStore: store,
      remote: remote,
    );
    addTearDown(coordinator.dispose);
    final report = await coordinator.syncNow();
    expect(report.conflicts, 1);
    expect(paths, isNot(contains('/sync/mutations')));
    final resolver = SyncConflictResolver(
      localSyncStore: store,
      generateNoteId: () => 'unused',
      generateMutationId: () => 'resolved-id',
      now: () => fixtureTime,
      accessGuard: _LocalGuard(),
    );
    await resolver.resolve(
      accountUserId: 'owner',
      conflict: store.state.conflicts.single,
      choice: SyncConflictChoice.useLocal,
    );
    expect(store.state.outbox.single.protectionChange, change());
    expect(store.state.outbox.single.operation, SyncMutationOperation.create);
    expect(store.state.outbox.single.baseRevision, 0);
    expect(store.state.notes.single.content, privateBody);
  });
}

final class _LocalGuard implements INoteAccessGuard {
  @override
  int get accessGeneration => 0;
  @override
  bool allows({
    required String ownerId,
    required String noteId,
    required NoteProtection protection,
    required NoteOperation operation,
  }) => true;
  @override
  void requireAccess({
    required String ownerId,
    required String noteId,
    required NoteProtection protection,
    required NoteOperation operation,
  }) {}
}
