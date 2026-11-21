@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_page.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_state_codec.dart';
import 'package:note_ai_app/infrastructure/security/paged_account_store.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store_io.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store_account_namespace.dart';

import 'paged_store_test.dart' show actor, repository;
import 'security_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late File root;
  EncryptedSyncStore open() => FileLocalSyncStore(
    accountUserId: actor,
    applicationSupportPathResolver: () async => support.path,
  );
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    support = await Directory.systemTemp.createTemp('note_paging_io_');
    root = File(
      '${support.path}/accounts/${LocalSyncAccountNamespace(actor).hash}/local_sync_state.json',
    );
  });
  tearDown(() async {
    final resolved = Directory(await support.resolveSymbolicLinks());
    final temp = Directory(await Directory.systemTemp.resolveSymbolicLinks());
    if (resolved.parent.path.toLowerCase() != temp.path.toLowerCase() ||
        !resolved.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last
            .startsWith('note_paging_io_')) {
      throw StateError('Unexpected test fixture path');
    }
    await resolved.delete(recursive: true);
  });

  test('native cutover keeps pending, fences legacy writer, cold reads only selected record', () async {
    final store = open();
    await store.replace(securityState(actor, pending: true));
    final oldCanonical = await root.readAsString();
    await repository(store).queryNotePage(actor, NotePageQuery(size: 1));
    final marker = jsonDecode(await root.readAsString()) as Map;
    expect(marker['schemaVersion'], 4);
    // The pre-pagination codec accepts ciphertext envelopes, not manifests.
    // Its raw CAS expectation also differs from the new root pointer.
    expect(await root.readAsString(), isNot(oldCanonical));
    final legacyDecoder = EncryptedStateCodec(LocalSyncAccountNamespace(actor));
    await expectLater(
      legacyDecoder.decode(await root.readAsString()),
      throwsA(anything),
    );
    legacyDecoder.dispose();
    final stale = open();
    expect(
      await stale.backing.compareAndSet('not-current', oldCanonical),
      false,
    );
    store.dispose();
    stale.dispose();
    final cold = open();
    final page = await repository(cold)
        .queryNotePage(actor, NotePageQuery(size: 1));
    expect(page.total, 2);
    expect(cold.codec.decodedAccountCount, 0);
    expect(cold.pagePayloadReads, 1);
    final restored = await cold.read();
    expect(restored.outbox.single.mutationId, 'stable-mutation-id');
    expect(restored.conflicts.single.remote!.content, 'private remote content');
    cold.dispose();
  });

  test(
    'failed preparation preserves old root; missing derived record repairs',
    () async {
      final store = open();
      await store.replace(securityState(actor, pending: true));
      final old = await root.readAsString();
      final blocker = File('${root.parent.path}/note_pages_v1');
      await blocker.writeAsString('owned test blocker');
      await expectLater(
        repository(store).queryNotePage(actor, NotePageQuery()),
        throwsA(anything),
      );
      expect(await root.readAsString(), old);
      await blocker.delete();
      final repo = repository(store);
      expect((await repo.queryNotePage(actor, NotePageQuery())).total, 2);
      final pages = Directory(blocker.path);
      final records = await pages
          .list()
          .where((f) => f.path.endsWith('.record'))
          .toList();
      await records.first.delete();
      await store.update((state) => state);
      expect((await repo.queryNotePage(actor, NotePageQuery())).total, 2);
      expect((await store.read()).outbox, hasLength(1));
      store.dispose();
    },
  );

  test(
    'native writers share atomic canonical/index CAS and generation fencing',
    () async {
      final a = open();
      await a.replace(securityState(actor, pending: true));
      await repository(a).queryNotePage(actor, NotePageQuery());
      final b = open();
      final expected = await a.backing.readEncoded();
      final state = await b.read();
      final pa = await a.codec.encodePageIndex(state);
      final pb = await b.codec.encodePageIndex(state);
      final encryptedA = await a.codec.encode(state);
      final encryptedB = await b.codec.encode(state);
      final results = await Future.wait([
        (a.backing as PagedAccountStore).compareAndSetPaged(
          expected,
          encryptedA,
          pa,
        ),
        (b.backing as PagedAccountStore).compareAndSetPaged(
          expected,
          encryptedB,
          pb,
        ),
      ]);
      expect(results.where((v) => v), hasLength(1));
      expect(
        (await repository(b).queryNotePage(actor, NotePageQuery())).total,
        2,
      );
      expect((await a.read()).outbox.single.retryCount, 3);
      a.dispose();
      b.dispose();
    },
  );

  test(
    'missing native commit pointer cannot seed an empty account over records',
    () async {
      final store = open();
      await store.replace(securityState(actor, pending: true));
      await repository(store).queryNotePage(actor, NotePageQuery());
      await root.delete();
      final cold = open();
      await expectLater(
        repository(cold).queryNotePage(actor, NotePageQuery()),
        throwsA(anything),
      );
      expect(await root.exists(), false);
      expect(
        await Directory('${root.parent.path}/note_pages_v1')
            .list()
            .where((f) => f.path.endsWith('.record'))
            .length,
        2,
      );
      store.dispose();
      cold.dispose();
    },
  );
}
