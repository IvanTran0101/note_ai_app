import '../../support/legacy_label_fields.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/attachment.dart';
import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/application/sync/sync_state_reconciliation.dart';
import 'package:note_ai_app/application/sync/sync_conflict.dart';
import 'package:note_ai_app/application/sync/sync_conflict_resolver.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_state_codec.dart';
import 'package:note_ai_app/infrastructure/sync/pending_mutation_codec.dart';
import 'package:note_ai_app/infrastructure/attachments/attachment_codec.dart';

import 'note_repository_test_support.dart';

final time = DateTime.utc(2026, 10, 4);
Attachment descriptor({String id = 'file-1', String noteId = 'note-1'}) =>
    Attachment(
      id: id,
      noteId: noteId,
      fileName: 'sample.txt',
      mimeType: 'text/plain',
      sizeBytes: 3,
      storageObjectId: 'object-1',
      objectVersion: 'version-1',
      sha256: 'a' * 64,
      addedAt: time,
    );

void main() {
  test(
    'aggregate freezes descriptors and rejects cross-note/duplicate versions',
    () {
      final input = [descriptor()];
      final note = Note.reconstitute(
        id: 'note-1',
        ownerId: 'user-1',
        title: 'Title',
        content: 'Body',
        createdAt: time,
        updatedAt: time,
        pinnedAt: time,
        attachments: input,
      );
      input.clear();
      expect(note.attachments, hasLength(1));
      expect(() => note.attachments.clear(), throwsUnsupportedError);
      note.addAttachment(descriptor(), time.add(const Duration(seconds: 1)));
      expect(note.updatedAt, time); // idempotent retry
      expect(
        () => note.addAttachment(descriptor(noteId: 'other'), time),
        throwsArgumentError,
      );
      note.replaceText('New', 'Body', time);
      expect(note.attachments, [descriptor()]);
      expect(note.pinnedAt, time);
    },
  );

  test('metadata roundtrip has no bytes, URL or credentials', () {
    final encoded = AttachmentCodec.encode(descriptor());
    expect(AttachmentCodec.decodeList([encoded], noteId: 'note-1'), [
      descriptor(),
    ]);
    expect(
      () => AttachmentCodec.decodeList([
        {...encoded, 'url': 'secret'},
      ]),
      throwsFormatException,
    );
    expect(
      () => AttachmentCodec.decodeList([
        {...encoded, 'sha256': 'bad'},
      ]),
      throwsFormatException,
    );
  });

  test('same writer preserves attempted payload, pin, preferences and concurrent text', () async {
    final attempted = PendingMutation(
      mutationId: 'attempted',
      noteId: 'note-1',
      operation: SyncMutationOperation.update,
      baseRevision: 1,
      payload: const SyncNotePayload(title: 'Old', content: 'Body'),
      createdAt: time,
      retryCount: 1,
    );
    final originalWire = PendingMutationCodec.encode(attempted);
    final store = FakeLocalSyncStore(
      accountUserId: 'user-1',
      initial: LocalSyncState(
        accountUserId: 'user-1',
        notes: [
          LocalNoteState(
            id: 'note-1',
            ownerId: 'user-1',
            title: 'Old',
            content: 'Body',
            createdAt: time,
            updatedAt: time,
            pinnedAt: time,
            serverRevision: 1,
          ),
        ],
        outbox: [attempted],
      ),
    );
    var mutationId = 0;
    final repository = NoteRepository(
      currentAccountUserId: () => 'user-1',
      localSyncStoreFactory: ({required accountUserId}) => store,
      generateMutationId: () => 'new-${++mutationId}',
      now: () => time,
    );
    await Future.wait([
      repository.updateById(
        noteId: 'note-1',
        ownerId: 'user-1',
        canCommit: () => true,
        expectedAccountUserId: 'user-1',
        change: (fresh) {
          fresh.addAttachment(descriptor(), time);
          return fresh;
        },
      ),
      repository.updateById(
        noteId: 'note-1',
        ownerId: 'user-1',
        canCommit: () => true,
        expectedAccountUserId: 'user-1',
        change: (fresh) {
          fresh.replaceText('Changed', 'New body', time);
          return fresh;
        },
      ),
    ]);
    final state = LocalSyncStateCodec.decode(
      LocalSyncStateCodec.encode(store.state),
    );
    expect(state.notes.single.title, 'Changed');
    expect(state.notes.single.attachments, [descriptor()]);
    expect(state.notes.single.pinnedAt, time);
    expect(state.userPreferences, store.state.userPreferences);
    expect(PendingMutationCodec.encode(state.outbox.first), originalWire);
    expect(state.outbox.last.payload!.attachments, [descriptor()]);
    expect(state.outbox.last.payload!.title, 'Changed');
  });

  test('legacy text-only ACK never clears attachment metadata', () async {
    final attempted = PendingMutation(
      mutationId: 'attempted',
      noteId: 'note-1',
      operation: SyncMutationOperation.update,
      baseRevision: 1,
      payload: const SyncNotePayload(title: 'Title', content: 'Body'),
      createdAt: time,
    );
    final store = FakeLocalSyncStore(
      accountUserId: 'user-1',
      initial: LocalSyncState(
        accountUserId: 'user-1',
        notes: [
          LocalNoteState(
            id: 'note-1',
            ownerId: 'user-1',
            title: 'Title',
            content: 'Body',
            createdAt: time,
            updatedAt: time,
            attachments: [descriptor()],
            serverRevision: 1,
          ),
        ],
        outbox: [attempted],
      ),
    );
    final reconciliation = SyncStateReconciliation(
      accountUserId: 'user-1',
      localStore: store,
      clock: () => time,
    );
    await reconciliation.acknowledge(
      attempted,
      SyncNoteSnapshot(
        id: 'note-1',
        title: 'Title',
        content: 'Body',
        createdAt: time,
        serverUpdatedAt: time,
        revision: 2,
      ),
    );
    expect(store.state.notes.single.attachments, [descriptor()]);
  });

  test('v3 migration preserves attempted bytes and account preferences', () {
    final state = LocalSyncState(
      accountUserId: 'user-1',
      notes: [
        LocalNoteState(
          id: 'note-1',
          ownerId: 'user-1',
          title: 'Title',
          content: 'Body',
          createdAt: time,
          updatedAt: time,
          pinnedAt: time,
        ),
      ],
    );
    final old = LocalSyncStateCodec.encode(state)..['schemaVersion'] = 3;
    stripM04Fields(old);
    (old['notes'] as List).single.remove('attachments');
    final migrated = LocalSyncStateCodec.decode(old);
    expect(migrated.notes, state.notes);
    expect(migrated.syncWireVersion, 1);
    expect(migrated.notes.single.attachments, isEmpty);
  });

  test(
    'a legacy ACK cannot falsely complete a mutation carrying attachments',
    () async {
      final pending = PendingMutation(
        mutationId: 'attempt',
        noteId: 'note-1',
        operation: SyncMutationOperation.update,
        baseRevision: 1,
        payload: SyncNotePayload(
          title: 'Title',
          content: 'Body',
          attachmentManifest: AttachmentManifest([
            descriptor(),
          ], noteId: 'note-1'),
          includesAttachments: true,
        ),
        createdAt: time,
      );
      final before = LocalSyncState(
        accountUserId: 'user-1',
        notes: [
          LocalNoteState(
            id: 'note-1',
            ownerId: 'user-1',
            title: 'Title',
            content: 'Body',
            createdAt: time,
            updatedAt: time,
            serverRevision: 1,
            attachments: [descriptor()],
          ),
        ],
        outbox: [pending],
      );
      final store = FakeLocalSyncStore(
        accountUserId: 'user-1',
        initial: before,
      );
      final reconciliation = SyncStateReconciliation(
        accountUserId: 'user-1',
        localStore: store,
        clock: () => time,
      );
      await expectLater(
        reconciliation.acknowledge(
          pending,
          SyncNoteSnapshot(
            id: 'note-1',
            title: 'Title',
            content: 'Body',
            revision: 2,
            createdAt: time,
            serverUpdatedAt: time,
          ),
        ),
        throwsA(
          isA<SyncFailure>().having(
            (e) => e.code,
            'code',
            SyncErrorCode.invalidMutation,
          ),
        ),
      );
      expect(store.state, before);
    },
  );

  test(
    'remote conflict choice distinguishes omitted and explicit empty manifests',
    () async {
      for (final explicitEmpty in [false, true]) {
        final local = LocalNoteState(
          id: 'note-1',
          ownerId: 'user-1',
          title: 'Local',
          content: 'Body',
          createdAt: time,
          updatedAt: time,
          attachments: [descriptor()],
        );
        final pending = PendingMutation(
          mutationId: 'attempt',
          noteId: 'note-1',
          operation: SyncMutationOperation.update,
          baseRevision: 1,
          payload: const SyncNotePayload(title: 'Local', content: 'Body'),
          createdAt: time,
        );
        final conflict = SyncConflict(
          noteId: 'note-1',
          local: local,
          pending: pending,
          detectedAt: time,
          remote: SyncNoteSnapshot(
            id: 'note-1',
            title: 'Remote',
            content: 'Body',
            revision: 2,
            createdAt: time,
            serverUpdatedAt: time,
            includesAttachments: explicitEmpty,
          ),
        );
        final store = FakeLocalSyncStore(
          accountUserId: 'user-1',
          initial: LocalSyncState(
            accountUserId: 'user-1',
            notes: [local],
            outbox: [pending],
            conflicts: [conflict],
          ),
        );
        await SyncConflictResolver(
          localSyncStore: store,
          generateNoteId: () => 'new',
          generateMutationId: () => 'new-mutation',
          now: () => time,
        ).resolve(
          accountUserId: 'user-1',
          conflict: conflict,
          choice: SyncConflictChoice.useRemote,
        );
        expect(store.state.notes.single.title, 'Remote');
        expect(
          store.state.notes.single.attachments,
          explicitEmpty ? isEmpty : [descriptor()],
        );
      }
    },
  );
}
