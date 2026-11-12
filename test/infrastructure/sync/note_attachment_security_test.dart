import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/sync_state_reconciliation.dart';
import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';
import 'package:note_ai_app/infrastructure/sync/local_note_state_codec.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_codec_exception.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_state_codec.dart';
import 'package:note_ai_app/infrastructure/sync/sync_http_mapper.dart';

import '../notes/attachment_metadata_test.dart' show descriptor;
import '../notes/note_repository_test_support.dart';

final time = DateTime.utc(2026, 10, 4);
final protected = NoteProtection(enabled: true, revision: 2);

Map<String, Object?> wire({bool secured = true, bool available = true}) => {
  'id': 'note-1',
  'ownerId': 'user-1',
  'title': 'Secret',
  'content': 'Body',
  'createdAt': time.toIso8601String(),
  'serverUpdatedAt': time.toIso8601String(),
  'revision': 2,
  'pinnedAt': time.toIso8601String(),
  if (secured) ...{
    'protected': true,
    'protectionRevision': 2,
    'contentAvailable': available,
  },
};

LocalNoteState local({bool secured = true}) => LocalNoteState(
  id: 'note-1',
  ownerId: 'user-1',
  title: 'Secret',
  content: 'Body',
  createdAt: time,
  updatedAt: time,
  pinnedAt: time,
  serverRevision: 1,
  protection: secured ? protected : const NoteProtection.unprotected(),
  attachments: [descriptor()],
);

void main() {
  test(
    'M05 metadata, attachments and M02 preferences survive state roundtrip',
    () {
      final state = LocalSyncState(accountUserId: 'user-1', notes: [local()]);
      expect(
        LocalSyncStateCodec.decode(LocalSyncStateCodec.encode(state)),
        state,
      );
    },
  );

  for (final field in ['protected', 'protectionRevision', 'contentAvailable']) {
    test(
      'partial security group without $field fails instead of downgrading',
      () {
        final json = wire()..remove(field);
        expect(() => decodeSyncNoteSnapshot(json), throwsFormatException);
        final record = LocalNoteStateCodec.encode(local())..remove(field);
        expect(
          () => LocalNoteStateCodec.decode(record),
          throwsA(isA<LocalSyncCodecException>()),
        );
      },
    );
  }

  test('sync feed cannot expose protected text or attachment filenames', () {
    final snapshot = decodeSyncNoteSnapshot(wire());
    expect(snapshot.protection, protected);
    expect(snapshot.contentAvailable, false);
    expect(snapshot.title, isEmpty);
    expect(snapshot.content, isEmpty);
    expect(snapshot.attachments, isEmpty);
    expect(snapshot.ownerId, 'user-1');
    final authorized = decodeSyncNoteSnapshot(wire(), authorizedContent: true);
    expect(authorized.contentAvailable, true);
    expect(authorized.title, 'Secret');
  });

  test(
    'redacted incoming state does not inherit old attachment descriptors',
    () async {
      final store = FakeLocalSyncStore(
        accountUserId: 'user-1',
        initial: LocalSyncState(accountUserId: 'user-1', notes: [local()]),
      );
      final reconciliation = SyncStateReconciliation(
        accountUserId: 'user-1',
        localStore: store,
        clock: () => time,
      );
      final incoming = reconciliation.fromRemote(
        decodeSyncNoteSnapshot(wire()),
        store.state.notes.single.status,
        previous: store.state.notes.single,
      );
      expect(incoming.attachments, isEmpty);
      expect(incoming.contentAvailable, false);
    },
  );

  test(
    'even an ACK with a later queued edit cannot strip security metadata',
    () async {
      PendingMutation mutation(String id) => PendingMutation(
        mutationId: id,
        noteId: 'note-1',
        operation: SyncMutationOperation.update,
        baseRevision: 1,
        payload: const SyncNotePayload(title: 'Secret', content: 'Body'),
        createdAt: time,
      );
      final attempted = mutation('attempt');
      final before = LocalSyncState(
        accountUserId: 'user-1',
        notes: [local()],
        outbox: [attempted, mutation('later')],
      );
      final store = FakeLocalSyncStore(
        accountUserId: 'user-1',
        initial: before,
      );
      await expectLater(
        SyncStateReconciliation(
          accountUserId: 'user-1',
          localStore: store,
          clock: () => time,
        ).acknowledge(attempted, decodeSyncNoteSnapshot(wire(secured: false))),
        throwsA(isA<SyncFailure>()),
      );
      expect(store.state, before);
    },
  );

  test(
    'repository without M05 authority redacts reads and rejects writes',
    () async {
      final before = LocalSyncState(accountUserId: 'user-1', notes: [local()]);
      final store = FakeLocalSyncStore(
        accountUserId: 'user-1',
        initial: before,
      );
      final repo = NoteRepository(
        currentAccountUserId: () => 'user-1',
        localSyncStoreFactory: ({required accountUserId}) => store,
        generateMutationId: () => 'm',
        now: () => time,
      );
      final redacted = await repo.findById('note-1');
      expect(redacted!.contentAvailable, false);
      expect(
        () => redacted.attachments,
        throwsA(isA<NoteContentUnavailable>()),
      );
      final dto = NoteDto.fromDomain(redacted);
      expect(dto.title, isEmpty);
      expect(dto.attachments, isEmpty);
      await expectLater(
        repo.updateById(
          noteId: 'note-1',
          ownerId: 'user-1',
          canCommit: () => true,
          expectedAccountUserId: 'user-1',
          change: (note) {
            note.removeAttachment('file-1', time);
            return note;
          },
        ),
        throwsA(isA<NoteSecurityFailure>()),
      );
      expect(store.state, before);
    },
  );

  test('stale aggregate cannot replace a newly protected local note', () async {
    final before = LocalSyncState(accountUserId: 'user-1', notes: [local()]);
    final store = FakeLocalSyncStore(accountUserId: 'user-1', initial: before);
    final repo = NoteRepository(
      currentAccountUserId: () => 'user-1',
      localSyncStoreFactory: ({required accountUserId}) => store,
      generateMutationId: () => 'm',
      now: () => time,
    );
    await expectLater(
      repo.save(
        Note.reconstitute(
          id: 'note-1',
          ownerId: 'user-1',
          title: 'Stale',
          content: 'Body',
          createdAt: time,
          updatedAt: time,
        ),
      ),
      throwsStateError,
    );
    expect(store.state, before);
  });
}
