import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/labels/label_application.dart';
import 'package:note_ai_app/application/notes/note_dto.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_cursor.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_state_codec.dart';
import 'package:note_ai_app/infrastructure/sync/sync_http_mapper.dart';

import '../../infrastructure/notes/note_repository_test_support.dart';

void main() {
  final now = DateTime.utc(2026, 10, 4);
  late FakeLocalSyncStore store;
  late NoteRepository notes;
  late LabelApplication labels;
  late String actor;
  var epoch = 1, id = 0, syncs = 0;
  setUp(() {
    actor = 'owner';
    epoch = 1;
    id = 0;
    syncs = 0;
    store = FakeLocalSyncStore(accountUserId: actor);
    notes = NoteRepository(
      labelsEnabled: true,
      currentAccountUserId: () => actor,
      localSyncStoreFactory: ({required accountUserId}) => store,
      generateMutationId: () => 'm${++id}',
      now: () => now,
      sessionGeneration: () => epoch,
    );
    labels = LabelApplication(
      currentActor: () => actor,
      generation: () => epoch,
      storeFor: (_) => store,
      notes: notes,
      generateId: () => 'l${++id}',
      now: () => now,
      requestSync: (_) => syncs++,
    );
  });
  tearDown(() => labels.dispose());
  Future<NoteDto> createNote() async {
    final n = Note.create(
      id: 'note',
      ownerId: actor,
      title: 'Title',
      content: 'Body',
      now: now,
    )..pin(now);
    await notes.save(n);
    return NoteDto.fromDomain(n);
  }

  test(
    'catalog CRUD persists locally with typed outbox; duplicates and no-op',
    () async {
      final a = await labels.create('Việt Nam'),
          b = await labels.create('Việt Nam');
      expect(a.id, isNot(b.id));
      expect((await labels.list()).length, 2);
      final count = store.replaceCount;
      await labels.rename(a.id, a.name);
      expect(store.replaceCount, count);
      await labels.rename(a.id, 'Học tập');
      final state = await store.read();
      expect(state.outbox.every((m) => m.isLabel), true);
      expect(state.outbox.length, 2);
      expect(state.outbox.first.mutation.labelName, 'Học tập');
      expect(
        encodeSyncMutation(state.outbox.first.toMutation())['entityType'],
        'label',
      );
      expect(syncs, 3);
    },
  );
  test(
    'attach detach uses fresh writer and preserves text pin and catalog',
    () async {
      final n = await createNote(), l = await labels.create('Work');
      final attached = await labels.setAttached(n, l.id, true);
      expect(attached.labelIds, [l.id]);
      expect(attached.pinnedAt, now);
      await notes.updateById(
        noteId: n.id,
        ownerId: actor,
        expectedAccountUserId: actor,
        canCommit: () => true,
        change: (fresh) {
          fresh.replaceText('Changed', 'Body2', now);
          return fresh;
        },
      );
      await labels.setAttached(n, l.id, false);
      final current = await notes.findById(n.id);
      expect(current!.title, 'Changed');
      expect(current.content, 'Body2');
      expect(current.pinnedAt, now);
      expect(current.labelIds, isEmpty);
      expect((await store.read()).labels.single.name, 'Work');
    },
  );
  test(
    'deleting a label preserves note and stale IDs across later text edits',
    () async {
      final n = await createNote(), l = await labels.create('Work');
      await labels.setAttached(n, l.id, true);
      await labels.delete(l.id);
      await notes.updateById(
        noteId: n.id,
        ownerId: actor,
        expectedAccountUserId: actor,
        canCommit: () => true,
        change: (fresh) {
          fresh.rename('Keep note', now);
          return fresh;
        },
      );
      final current = await notes.findById(n.id);
      expect(current!.labelIds, [l.id]);
      expect(current.title, 'Keep note');
      await expectLater(labels.setAttached(n, l.id, true), throwsStateError);
      await labels.setAttached(n, l.id, false);
    },
  );
  test('same ID note and label never coalesce or drop each other', () async {
    await createNote();
    final l = await labels.create('Work');
    final n = Note.create(
      id: l.id,
      ownerId: actor,
      title: 'Same ID',
      content: 'C',
      now: now,
    );
    await notes.save(n);
    await labels.rename(l.id, 'Renamed');
    final state = await store.read();
    expect(state.outbox.where((m) => m.noteId == l.id).length, 2);
    expect(
      state.outbox
          .where((m) => m.noteId == l.id)
          .map((m) => m.keyFor(actor))
          .toSet()
          .length,
      2,
    );
  });
  test(
    'attempted label rename keeps old request bytes and creates successor',
    () async {
      final l = await labels.create('Old');
      final old = (await store.read()).outbox.single;
      await store.update(
        (s) => LocalSyncState(
          accountUserId: actor,
          labels: s.labels,
          outbox: [
            PendingMutation(
              mutationId: old.mutationId,
              noteId: l.id,
              entityType: SyncEntityType.label,
              labelName: 'Old',
              operation: old.operation,
              baseRevision: old.baseRevision,
              createdAt: old.createdAt,
              retryCount: 1,
            ),
          ],
        ),
      );
      final bytes = jsonEncode(
        encodeSyncMutation((await store.read()).outbox.single.toMutation()),
      );
      await labels.rename(l.id, 'New');
      final state = await store.read();
      expect(
        jsonEncode(encodeSyncMutation(state.outbox.first.toMutation())),
        bytes,
      );
      expect(state.outbox.last.baseRevision, 1);
      expect(state.outbox.last.mutationId, isNot(old.mutationId));
    },
  );
  test(
    'foreign actor and failed durability cannot grant or queue labels',
    () async {
      final n = await createNote(), l = await labels.create('Work');
      actor = 'other';
      epoch++;
      await expectLater(
        labels.setAttached(n, l.id, true),
        throwsA(isA<SyncFailure>()),
      );
      actor = 'owner';
      epoch++;
      store.failure = StateError('disk');
      await expectLater(labels.rename(l.id, 'Lost'), throwsStateError);
      expect((await store.read()).labels.single.name, 'Work');
    },
  );
  test(
    'schema6 roundtrip preserves catalog, pending labels and note membership',
    () async {
      final n = await createNote(), l = await labels.create('Work');
      await labels.setAttached(n, l.id, true);
      final state = await store.read();
      expect(
        LocalSyncStateCodec.decode(
          jsonDecode(jsonEncode(LocalSyncStateCodec.encode(state))),
        ),
        state,
      );
    },
  );
  test('migration5 preserves cursor and exact attempted v1 request', () async {
    final mutation = PendingMutation(
      mutationId: 'legacy',
      noteId: 'n',
      operation: SyncMutationOperation.create,
      baseRevision: 0,
      payload: const SyncNotePayload(title: 'T', content: 'C'),
      createdAt: now,
      retryCount: 1,
    );
    final raw = LocalSyncStateCodec.encode(
      LocalSyncState(
        accountUserId: actor,
        cursor: const SyncCursor('opaque'),
        outbox: [mutation],
      ),
    );
    raw['schemaVersion'] = 5;
    raw.remove('labels');
    raw.remove('syncWireVersion');
    final migrated = LocalSyncStateCodec.decode(raw);
    expect(migrated.cursor, const SyncCursor('opaque'));
    expect(migrated.syncWireVersion, 1);
    expect(
      encodeSyncMutation(migrated.outbox.single.toMutation()),
      encodeSyncMutation(mutation.toMutation()),
    );
  });
}
