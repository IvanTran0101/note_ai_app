import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_dto.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_role.dart';
import 'package:note_ai_app/domain/notes/note_share_grant.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store.dart';

void registerEditorEvidenceScenarios() {
  test('real platform unsaved shared editor evidence survives reopen encrypted without outbox', () async {
    final actor = 'm06-editor-${DateTime.now().microsecondsSinceEpoch}';
    final at = DateTime.utc(2026, 10, 2);
    final grant = NoteShareGrant(
      note: NoteIdentity('owner', 'same'),
      recipientId: actor,
      role: NoteRole.editor,
      sharedAt: at,
      updatedAt: at,
      accessRevision: 3,
    );
    final selected = NoteDto(
      id: 'same',
      ownerId: 'owner',
      title: 'shared',
      content: 'saved',
      createdAt: at,
      updatedAt: at,
      contentRevision: 7,
      share: grant,
    );
    final store =
        createLocalSyncStore(accountUserId: actor) as EncryptedSyncStore;
    await store.replace(
      LocalSyncState(
        accountUserId: actor,
        notes: [
          LocalNoteState(
            id: 'same',
            ownerId: 'owner',
            share: grant,
            title: 'shared',
            content: 'saved',
            createdAt: at,
            updatedAt: at,
            serverRevision: 7,
          ),
        ],
      ),
    );
    final before = await store.read();
    await store.retainEditorDraft(
      selected,
      'UNSAVED-TITLE-M06',
      'UNSAVED-CONTENT-M06',
    );
    expect(await store.read(), before);
    final encoded = (await store.backing.readEncoded())!;
    expect(encoded.contains('UNSAVED-TITLE-M06'), false);
    expect(encoded.contains('UNSAVED-CONTENT-M06'), false);
    expect(store.hasRetainedCiphertext(selected.reference), true);
    store.dispose();
    final reopened =
        createLocalSyncStore(accountUserId: actor) as EncryptedSyncStore;
    addTearDown(reopened.dispose);
    expect((await reopened.read()).outbox, isEmpty);
    expect(reopened.hasRetainedCiphertext(selected.reference), true);
  });
}
