@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indexed_db/indexed_db.dart';
import 'package:note_ai_app/application/notes/note_page.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_state_codec.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';
import 'package:note_ai_app/infrastructure/security/paged_account_store.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store_web.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store_account_namespace.dart';

import 'security_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('IDB3 page reopen, atomic CAS and legacy version fencing', () async {
    final actor = 'paging-web-${DateTime.now().microsecondsSinceEpoch}';
    EncryptedSyncStore open() => IndexedDbLocalSyncStore(accountUserId: actor);
    NoteRepository repo(EncryptedSyncStore store) => NoteRepository(
      currentAccountUserId: () => actor,
      localSyncStoreFactory: ({required accountUserId}) => store,
      generateMutationId: () => 'unused',
      now: () => fixtureTime,
    );
    final a = open();
    await a.replace(securityState(actor, pending: true));
    expect(
      (await repo(a).queryNotePage(actor, NotePageQuery(size: 1))).total,
      2,
    );
    final b = open();
    expect(
      (await repo(b).queryNotePage(actor, NotePageQuery(size: 1))).notes,
      hasLength(1),
    );
    expect(b.codec.decodedAccountCount, 0);
    expect(b.pagePayloadReads, 1);
    final expected = await a.backing.readEncoded();
    final state = await b.read();
    final pa = await a.codec.encodePageIndex(state);
    final pb = await b.codec.encodePageIndex(state);
    final sealedA = await a.codec.encode(state);
    final sealedB = await b.codec.encode(state);
    final results = await Future.wait([
      (a.backing as PagedAccountStore).compareAndSetPaged(
        expected,
        sealedA,
        pa,
      ),
      (b.backing as PagedAccountStore).compareAndSetPaged(
        expected,
        sealedB,
        pb,
      ),
    ]);
    expect(results.where((v) => v), hasLength(1));
    await expectLater(
      IdbFactory().open(
        LocalSyncAccountNamespace(actor).webDatabaseName,
        version: 2,
      ),
      throwsA(anything),
    );
    final db = await IdbFactory().open(
      LocalSyncAccountNamespace(actor).webDatabaseName,
    );
    final tx = db.transactionList(['note_page_records_v1'], 'readwrite');
    await tx.objectStore('note_page_records_v1').clear();
    await tx.completed;
    db.close();
    // Derived ciphertext loss repairs through the canonical CAS, not empty seed.
    await b.update((state) => state);
    expect((await repo(b).queryNotePage(actor, NotePageQuery())).total, 2);
    expect((await b.read()).outbox.single.mutationId, 'stable-mutation-id');
    expect((await b.read()).conflicts, hasLength(1));
    a.dispose();
    b.dispose();
  });

  test('IDB transaction abort rolls back canonical, index and note records together', () async {
    final actor = 'paging-web-abort-${DateTime.now().microsecondsSinceEpoch}';
    final store = IndexedDbLocalSyncStore(accountUserId: actor);
    await store.replace(securityState(actor, pending: true));
    await store.withNotePageView((view) async => view.headers.length);
    final canonical = await store.backing.readEncoded();
    final original = await (store.backing as PagedAccountStore).openPagedView();
    final db = await IdbFactory().open(
      LocalSyncAccountNamespace(actor).webDatabaseName,
    );
    final tx = db.transactionList([
      'local_sync_state',
      'note_page_meta_v1',
      'note_page_records_v1',
    ], 'readwrite');
    final completed = expectLater(tx.completed, throwsA(anything));
    await tx.objectStore('local_sync_state').put('invalid'.toJS, 'state'.toJS);
    await tx.objectStore('note_page_meta_v1').put('invalid'.toJS, 'head'.toJS);
    await tx.objectStore('note_page_records_v1').clear();
    tx.abort();
    await completed;
    db.close();
    expect(await store.backing.readEncoded(), canonical);
    expect(
      (await (store.backing as PagedAccountStore).openPagedView())!.generation,
      original!.generation,
    );
    expect(
      await store.withNotePageView(
        (view) async => (await view.readNote(view.headers.first)).content,
      ),
      privateBody,
    );
    final damaged = await IdbFactory().open(
      LocalSyncAccountNamespace(actor).webDatabaseName,
    );
    final remove = damaged.transactionList(['local_sync_state'], 'readwrite');
    await remove.objectStore('local_sync_state').delete('state'.toJS);
    await remove.completed;
    damaged.close();
    final cold = IndexedDbLocalSyncStore(accountUserId: actor);
    await expectLater(cold.read(), throwsA(anything));
    expect(
      (await (cold.backing as PagedAccountStore).openPagedView())!.generation,
      original.generation,
    );
    cold.dispose();
    store.dispose();
  });
}
