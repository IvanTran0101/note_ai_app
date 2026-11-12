import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/account_realtime_service.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/revision_source.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/infrastructure/sync/sync_http_mapper.dart';

import '../application/sync/sync_coordinator_service_test.dart' as fixtures;
import 'realtime_protocol_test.dart' as protocol;

void main() {
  test('eventual feed flag is additive and strictly decoded', () {
    final page = decodeChangesPage(
      jsonEncode({
        'items': [],
        'hasMore': false,
        'nextCursor': 'prefix',
        'catchUpPending': true,
      }),
    );
    expect(page.catchUpPending, true);
    expect(
      decodeChangesPage(jsonEncode({'items': [], 'hasMore': false}))
          .catchUpPending,
      false,
    );
    expect(
      () => decodeChangesPage(
        jsonEncode({'items': [], 'catchUpPending': 'true'}),
      ),
      throwsFormatException,
    );
  });
  test('early signal retries saved cursor until eventual GSI visibility catches up', () async {
    final store = fixtures.MemoryStore(LocalSyncState(accountUserId: 'acct'));
    var pulls = 0;
    final remote = fixtures.FakeRemote()
      ..onPull = (cursor, limit) async {
        pulls++;
        if (pulls == 1) {
          return SyncChangesPage(
            snapshots: [],
            nextCursor: 'prefix',
            catchUpPending: true,
          );
        }
        expect(cursor, 'prefix');
        return SyncChangesPage(
          snapshots: [
            SyncNoteSnapshot(
              id: 'n',
              title: 'caught up',
              content: 'body',
              revision: 1,
              createdAt: DateTime.utc(2030),
              serverUpdatedAt: DateTime.utc(2030),
            ),
          ],
          nextCursor: 'caught-up',
        );
      };
    final coordinator = fixtures.service(store, remote);
    final source = protocol.NoticeFixture();
    final realtime = AccountRealtimeService(
      source: source,
      isCurrentSession: () => true,
      retryDelay: const Duration(milliseconds: 20),
      synchronize: () async {
        await coordinator.syncNow();
      },
    );
    addTearDown(() async {
      await realtime.dispose();
      await coordinator.dispose();
    });
    realtime.start();
    source.events.add(const RevisionNotice.connected());
    await protocol.tick(80);
    expect(pulls, 2);
    expect(store.state.notes.single.title, 'caught up');
    expect(store.state.cursor?.value, 'caught-up');
    expect(store.state.outbox, isEmpty);
  });
}
