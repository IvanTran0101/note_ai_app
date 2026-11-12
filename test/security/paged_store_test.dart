import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/notes/note_security_service.dart';
import 'package:note_ai_app/application/notes/note_page.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_state_codec.dart';
import 'package:note_ai_app/infrastructure/security/paged_account_store.dart';

import 'paged_store_fixture.dart';
import 'security_fixtures.dart';
import 'local_first_scenarios.dart' show localService, unsynced;

const actor = 'paging-test-owner';
NoteRepository repository(EncryptedSyncStore store) => NoteRepository(
  currentAccountUserId: () => actor,
  localSyncStoreFactory: ({required accountUserId}) => store,
  generateMutationId: () => 'test-mutation',
  now: () => fixtureTime,
);

LocalSyncState thousand() => LocalSyncState(
  accountUserId: actor,
  notes: List.generate(
    1000,
    (i) => LocalNoteState(
      id: 'n${i.toString().padLeft(4, '0')}',
      ownerId: actor,
      title: 'Note $i',
      content: 'Full text unique-marker-$i!',
      createdAt: fixtureTime,
      updatedAt: fixtureTime,
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'password enable removes account-key payload, cold unlock stays in vault',
    () async {
      final disk = MemoryPagedStore();
      final store = EncryptedSyncStore(actor, disk);
      await store.replace(unsynced(actor));
      final repo = repository(store);
      await repo.queryNotePage(actor, NotePageQuery());
      expect(disk.records, hasLength(2));
      final service = localService(actor, store);
      await service.enable('alpha', securityPassword, securityPassword);
      expect(disk.records, hasLength(1));
      final page = await repo.queryNotePage(actor, NotePageQuery());
      expect(page.notes.where((n) => n.id == 'alpha').single.content, '');
      service.dispose();
      store.dispose();
      final cold = EncryptedSyncStore(actor, disk);
      final security = localService(actor, cold);
      await expectLater(
        security.unlock('alpha', 'bad', offline: true),
        throwsA(isA<NoteSecurityFailure>()),
      );
      await security.unlock('alpha', securityPassword, offline: true);
      expect((await cold.read()).notes.first.content, privateBody);
      expect(disk.records, hasLength(1));
      security.dispose();
      cold.dispose();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    '1000-note migration then cold pages decode 50 payloads and no account',
    () async {
      final disk = MemoryPagedStore();
      final initial = EncryptedSyncStore(actor, disk);
      await initial.replace(thousand());
      final canonical = disk.canonical;
      final first = await repository(initial)
          .queryNotePage(actor, NotePageQuery());
      expect(first.total, 1000);
      expect(first.notes, hasLength(50));
      expect(disk.canonical, canonical);
      expect(disk.records, hasLength(1000));
      expect(disk.view!.index, isNot(contains('unique-marker')));
      expect(
        disk.records.values.any((v) => v.contains('unique-marker')),
        isFalse,
      );
      initial.codec.dispose();
      final cold = EncryptedSyncStore(actor, disk);
      final repo = repository(cold);
      final page = await repo.queryNotePage(actor, NotePageQuery(page: 19));
      expect(page.notes, hasLength(50));
      expect(page.notes.last.content, contains('999!'));
      expect(cold.codec.decodedAccountCount, 0);
      expect(cold.pagePayloadReads, 50);
      expect((await repo.findById('n0000'))!.content, contains('0!'));
      expect(cold.pagePayloadReads, 51);
      expect(cold.codec.decodedAccountCount, 0);
      cold.codec.dispose();
    },
  );

  test(
    'global full-text scans sequential records, not the canonical snapshot',
    () async {
      final disk = MemoryPagedStore();
      final store = EncryptedSyncStore(actor, disk);
      await store.replace(thousand());
      final repo = repository(store);
      await repo.queryNotePage(actor, NotePageQuery());
      store.codec.decodedAccountCount = 0;
      store.pagePayloadReads = 0;
      final match = await repo.queryNotePage(
        actor,
        NotePageQuery(keyword: 'unique-marker-999!'),
      );
      expect(match.total, 1);
      expect(match.notes.single.id, 'n0999');
      expect(store.codec.decodedAccountCount, 0);
      expect(store.pagePayloadReads, 1001);
      store.codec.dispose();
    },
  );

  test('damaged derived record/index repairs from canonical without losing outbox/conflicts', () async {
    final disk = MemoryPagedStore();
    final store = EncryptedSyncStore(actor, disk);
    await store.replace(securityState(actor, pending: true));
    final repo = repository(store);
    await repo.queryNotePage(actor, NotePageQuery());
    final canonical = disk.canonical;
    disk.records[disk.records.keys.first] = '{}';
    expect((await repo.queryNotePage(actor, NotePageQuery())).total, 2);
    disk.view = PagedEncodedView(
      disk.view!.generation,
      '{"schemaVersion":1,"keyId":7,"packet":{}}',
    );
    expect((await repo.queryNotePage(actor, NotePageQuery())).total, 2);
    expect(disk.canonical, canonical);
    final recovered = await store.read();
    expect(recovered.outbox.single.mutationId, 'stable-mutation-id');
    expect(recovered.conflicts, hasLength(1));
    expect(recovered.cursor, isNotNull);
    store.codec.dispose();
  });

  test(
    'failed migration CAS leaves canonical and all pending evidence untouched',
    () async {
      final disk = MemoryPagedStore();
      final store = EncryptedSyncStore(actor, disk);
      await store.replace(securityState(actor, pending: true));
      final canonical = disk.canonical;
      disk.rejectedCommits = 30;
      await expectLater(
        repository(store).queryNotePage(actor, NotePageQuery()),
        throwsA(isA<NoteSecurityFailure>()),
      );
      expect(disk.canonical, canonical);
      expect(disk.records, isEmpty);
      expect(disk.view, isNull);
      store.codec.dispose();
    },
  );

  test('epoch change during payload await denies the page', () async {
    final disk = MemoryPagedStore();
    final store = EncryptedSyncStore(actor, disk);
    await store.replace(securityState(actor));
    final repo = repository(store);
    await repo.queryNotePage(actor, NotePageQuery());
    disk.beforeRecord = () => store.codec.lock(null);
    await expectLater(
      repo.queryNotePage(actor, NotePageQuery()),
      throwsA(isA<NoteSecurityFailure>()),
    );
    store.codec.dispose();
  });

  test('cross-context generation change retries without mixed rows', () async {
    final disk = MemoryPagedStore();
    final store = EncryptedSyncStore(actor, disk);
    final state = securityState(actor);
    await store.replace(state);
    final repo = repository(store);
    await repo.queryNotePage(actor, NotePageQuery());
    final replacement = await store.codec.encodePageIndex(state);
    disk.beforeRecord = () {
      disk.view = PagedEncodedView(replacement.generation, replacement.index);
      disk.records
        ..clear()
        ..addAll(replacement.upserts);
    };
    expect(
      (await repo.queryNotePage(actor, NotePageQuery())).notes,
      hasLength(2),
    );
    expect(disk.view!.generation, replacement.generation);
    store.dispose();
  });

  test(
    'missing device key fails closed without regenerating or replacing storage',
    () async {
      final disk = MemoryPagedStore();
      final store = EncryptedSyncStore(actor, disk);
      await store.replace(securityState(actor, pending: true));
      await repository(store).queryNotePage(actor, NotePageQuery());
      final original = disk.canonical;
      final generation = disk.view!.generation;
      store.dispose();
      FlutterSecureStorage.setMockInitialValues({});
      final cold = EncryptedSyncStore(actor, disk);
      await expectLater(
        repository(cold).queryNotePage(actor, NotePageQuery()),
        throwsA(isA<NoteSecurityFailure>()),
      );
      expect(disk.canonical, original);
      expect(disk.view!.generation, generation);
      cold.dispose();
    },
  );

  test('subsequent mutation updates page generation and reuses unchanged ciphertext', () async {
    final disk = MemoryPagedStore();
    final store = EncryptedSyncStore(actor, disk);
    await store.replace(securityState(actor, pending: true));
    final repo = repository(store);
    await repo.queryNotePage(actor, NotePageQuery());
    final old = disk.view!.generation;
    await store.update((state) => state); // Still a real canonical CAS.
    expect(disk.view!.generation, isNot(old));
    expect(disk.lastUpserts, 0);
    await expectLater(
      disk.requirePagedGeneration(old),
      throwsA(isA<StalePageRead>()),
    );
    expect((await store.read()).outbox.single.retryCount, 3);
    store.codec.dispose();
  });
}
