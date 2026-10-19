import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/notes/note_editor_snapshot.dart';
import 'package:note_ai_app/application/sync/sync_metadata_projection.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/domain/notes/note_share_grant.dart';
import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_state_codec.dart';
import 'package:note_ai_app/infrastructure/sync/note_share_grant_codec.dart';
import 'package:note_ai_app/infrastructure/sync/sync_http_mapper.dart';

import '../../security/security_fixtures.dart'
    show MemoryCiphertextStore, securityPassword;
import 'm09_storage_fixtures.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'copy adapter preserves document and refuses a stale plain body',
    () async {
      final store = EncryptedSyncStore('owner', MemoryCiphertextStore());
      addTearDown(store.dispose);
      final controller = NoteApplicationServiceController(fixture.app(store));
      final document = fixture.doc(bold: true);
      final copy = await controller.createSnapshotNote(
        title: 'Copy',
        content: document.plainText,
        document: document,
      );
      expect(copy.document, document);
      final before = await store.read();
      await expectLater(
        controller.createSnapshotNote(
          title: 'Copy',
          content: 'stale text',
          document: document,
        ),
        throwsA(isA<NoteDocumentStorageUnavailable>()),
      );
      expect(await store.read(), before);
    },
  );

  test(
    'direct legacy save cannot discard a previously rich document',
    () async {
      final store = EncryptedSyncStore('owner', MemoryCiphertextStore());
      addTearDown(store.dispose);
      await store.replace(fixture.state());
      final app = fixture.app(store);
      final current = fixture.note();
      await expectLater(
        app.noteRepository.save(
          Note.reconstitute(
            id: current.id,
            ownerId: current.ownerId,
            title: current.title,
            content: current.content,
            createdAt: current.createdAt,
            updatedAt: current.updatedAt,
            pinnedAt: current.pinnedAt,
            attachments: current.attachments,
            labelIds: current.labelIds,
            contentRevision: current.serverRevision,
          ),
        ),
        throwsArgumentError,
      );
      expect((await store.read()).notes.single.document, fixture.doc());
      expect((await store.read()).outbox, isEmpty);
    },
  );

  test(
    'new empty document is a real rich note without fake plain body',
    () async {
      final store = EncryptedSyncStore('owner', MemoryCiphertextStore());
      addTearDown(store.dispose);
      final app = fixture.app(store);
      final document = NoteDocument([]);
      final created = await app.createNote(
        title: 'Empty rich',
        content: '',
        document: document,
      );
      expect(created.document, document);
      final saved = await store.read();
      expect(saved.notes.single.content, isEmpty);
      expect(saved.notes.single.document, document);
      expect(saved.outbox.single.payload!.includesDocument, true);
      expect(saved.outbox.single.payload!.document, document);
    },
  );

  test('real writer atomically stores format-only document/projection/outbox and metadata', () async {
    final backing = MemoryCiphertextStore();
    final store = EncryptedSyncStore('owner', backing);
    addTearDown(store.dispose);
    await store.replace(fixture.state());
    final syncs = <String>[];
    final app = fixture.app(store, syncs: syncs);
    final selected = await app.readNote('n');
    await app.saveDocumentSnapshot(
      selected,
      selected.title,
      fixture.doc(bold: true),
    );
    final saved = await store.read();
    expect(saved.notes.single.document, fixture.doc(bold: true));
    expect(saved.notes.single.content, fixture.doc().plainText);
    expect(saved.outbox.single.payload!.document, fixture.doc(bold: true));
    expect(saved.notes.single.attachments, [fixture.attachment]);
    expect(saved.notes.single.labelIds, ['label']);
    expect(saved.notes.single.pinnedAt, fixture.at);
    expect(saved.cursor!.value, 'cursor');
    expect(syncs, ['owner']);
    expect(backing.encoded, isNot(contains('private rich')));
    expect(backing.encoded, isNot(contains('fontSize')));
    final reopened = EncryptedSyncStore('owner', backing);
    addTearDown(reopened.dispose);
    expect(await reopened.read(), saved);
    await app.saveDocumentSnapshot(
      await app.readNote('n'),
      'Title',
      fixture.doc(bold: true),
    );
    expect((await store.read()).outbox.length, 1);
    expect(syncs.length, 1);
  });

  test(
    'attempted legacy request stays identical while rich successor is queued',
    () async {
      final backing = MemoryCiphertextStore();
      final store = EncryptedSyncStore('owner', backing);
      addTearDown(store.dispose);
      await store.replace(
        fixture.state(rich: false, queued: true, retryCount: 3),
      );
      final before = (await store.read()).outbox.single;
      final request = jsonEncode(encodeSyncMutation(before.toMutation()));
      final app = fixture.app(store);
      await app.saveDocumentSnapshot(
        await app.readNote('n'),
        'Title',
        fixture.doc(),
      );
      final entries = (await store.read()).outbox;
      expect(entries.first, before);
      expect(
        jsonEncode(encodeSyncMutation(entries.first.toMutation())),
        request,
      );
      expect(entries.last.baseRevision, 8);
      expect(entries.last.mutationId, isNot(before.mutationId));
      expect(entries.last.payload!.document, fixture.doc());
    },
  );

  test(
    'CAS exhaustion leaves durable document/outbox unchanged and emits no sync',
    () async {
      final backing = MemoryCiphertextStore();
      final store = EncryptedSyncStore('owner', backing);
      addTearDown(store.dispose);
      await store.replace(fixture.state());
      final original = backing.encoded;
      final syncs = <String>[];
      final app = fixture.app(store, syncs: syncs);
      final selected = await app.readNote('n');
      backing.failCommits = 5;
      await expectLater(
        app.saveDocumentSnapshot(selected, 'Title', fixture.doc(bold: true)),
        throwsA(isA<NoteSecurityFailure>()),
      );
      expect(backing.encoded, original);
      expect((await store.read()).notes.single.document, fixture.doc());
      expect((await store.read()).outbox, isEmpty);
      expect(syncs, isEmpty);
    },
  );

  test(
    'password lock/reopen/unlock keeps rich document and frozen work encrypted',
    () async {
      final backing = MemoryCiphertextStore();
      final store = EncryptedSyncStore('owner', backing);
      addTearDown(store.dispose);
      final protection = NoteProtection(enabled: true, revision: 1);
      await store.replace(fixture.state(queued: true, retryCount: 3));
      await store.seal('n', securityPassword, protection);
      store.lock('n');
      final locked = await store.read();
      expect(locked.notes.single.document, null);
      expect(locked.outbox.single.payload!.document, null);
      expect(
        jsonEncode(LocalSyncStateCodec.encode(locked)),
        isNot(contains('fontSize')),
      );
      final reopened = EncryptedSyncStore('owner', backing);
      addTearDown(reopened.dispose);
      await reopened.unlock('n', securityPassword, protection);
      final restored = await reopened.read();
      expect(restored.notes.single.document, fixture.doc());
      expect(restored.outbox.single.payload!.document, fixture.doc());
      expect(restored.outbox.single.retryCount, 3);
      expect(restored.outbox.single.mutationId, 'attempt');
      expect(
        SyncMetadataProjection.state(restored).notes.single.document,
        null,
      );
      expect(backing.encoded, isNot(contains('private rich')));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('revoke masks rich data and retains encrypted work without new-grant replay', () async {
    final backing = MemoryCiphertextStore();
    final store = EncryptedSyncStore('actor', backing);
    addTearDown(store.dispose);
    final oldGrant = fixture.grant();
    await store.replace(fixture.state(share: oldGrant, queued: true));
    await store.retainDocumentDraft(
      NoteDto.fromLocalState(fixture.note(share: oldGrant)),
      'Draft',
      fixture.doc(bold: true),
    );
    final revoked = fixture.grant(revision: 2, status: NoteShareStatus.revoked);
    await store.update(
      (current) => LocalSyncStateCodec.decode({
        ...LocalSyncStateCodec.encode(current),
        'notes': [
          {
            ...(LocalSyncStateCodec.encode(current)['notes'] as List).single
                as Map,
            'title': '',
            'content': '',
            'document': null,
            'attachments': [],
            'labelIds': [],
            'labelProjections': [],
            'contentAvailable': false,
            'share': NoteShareGrantCodec.encode(revoked),
          },
        ],
        'outbox': (LocalSyncStateCodec.encode(current)['outbox'] as List)
            .map((m) => {...m as Map, 'blocked': true})
            .toList(),
      }),
    );
    final revokedState = await store.read();
    expect(revokedState.notes.single.document, null);
    expect(revokedState.outbox.single.payload!.document, null);
    expect(revokedState.outbox.single.blocked, true);
    expect(
      store.hasRetainedCiphertext(
        fixture.note(share: oldGrant).referenceFor('actor'),
      ),
      true,
    );
    expect(backing.encoded, isNot(contains('private rich')));
    expect(backing.encoded, isNot(contains('fontSize')));
    await store.hydrate(
      fixture.snapshot(
        document: fixture.doc(bold: true),
        share: fixture.grant(revision: 3),
      ),
    );
    final newGrant = await store.read();
    expect(newGrant.notes.single.document, fixture.doc(bold: true));
    expect(newGrant.outbox.single.mutationId, 'attempt');
    expect(newGrant.outbox.single.accessRevision, 1);
    expect(newGrant.outbox.single.payload!.document, null);
    expect(newGrant.outbox.single.blocked, true);
  });
}
