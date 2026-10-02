import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_role.dart';
import 'package:note_ai_app/domain/notes/note_share_grant.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_state_codec.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_codec_exception.dart';

void main() {
  final at = DateTime.utc(2026, 10, 2);
  final share = NoteShareGrant(
    note: NoteIdentity('owner', 'same'),
    recipientId: 'actor',
    role: NoteRole.editor,
    sharedAt: at,
    updatedAt: at,
    accessRevision: 1,
  );
  LocalNoteState note(
    String owner, {
    NoteShareGrant? grant,
    bool available = true,
  }) => LocalNoteState(
    id: 'same',
    ownerId: owner,
    title: available ? 'title' : '',
    content: available ? 'body' : '',
    createdAt: at,
    updatedAt: at,
    share: grant,
    contentAvailable: available,
  );
  test('owned and foreign same-id notes round trip in one actor namespace', () {
    final pending = PendingMutation(
      mutationId: 'stable',
      noteId: 'same',
      ownerId: 'owner',
      accessRevision: 1,
      operation: SyncMutationOperation.update,
      baseRevision: 7,
      payload: const SyncNotePayload(title: 'draft', content: 'draft'),
      createdAt: at,
      retryCount: 3,
    );
    final state = LocalSyncState(
      accountUserId: 'actor',
      notes: [
        note('actor'),
        note('owner', grant: share),
      ],
      outbox: [pending],
    );
    final encoded = LocalSyncStateCodec.encode(state);
    expect(LocalSyncStateCodec.decode(encoded), state);
    expect(state.notes[0].referenceFor('actor'), 'same');
    expect(state.notes[1].referenceFor('actor'), share.note.key);
    expect(state.outbox.single.mutation.identityFor('actor'), share.note);
  });
  test(
    'foreign content requires a grant matching actor and canonical note',
    () {
      expect(
        () => LocalSyncState(
          accountUserId: 'stranger',
          notes: [note('owner', grant: share)],
        ),
        throwsArgumentError,
      );
      expect(
        () => LocalSyncState(accountUserId: 'actor', notes: [note('owner')]),
        throwsArgumentError,
      );
      expect(() => note('other', grant: share), throwsArgumentError);
      final revoked = share.revoke('owner', at);
      expect(
        () => LocalSyncState(
          accountUserId: 'actor',
          notes: [note('owner', grant: revoked)],
        ),
        throwsArgumentError,
      );
      expect(
        LocalSyncState(
          accountUserId: 'actor',
          notes: [note('owner', grant: revoked, available: false)],
        ).notes,
        hasLength(1),
      );
    },
  );
  test(
    'legacy owned encoding stays unchanged, additive fields stay strict',
    () {
      final encoded = LocalSyncStateCodec.encode(
        LocalSyncState(accountUserId: 'actor', notes: [note('actor')]),
      );
      final record = (encoded['notes'] as List).single as Map;
      expect(record.containsKey('share'), false);
      record['unexpected'] = 'private';
      expect(
        () => LocalSyncStateCodec.decode(encoded),
        throwsA(isA<LocalSyncCodecException>()),
      );
    },
  );
  test('share role, recipient and access epoch cannot silently decode malformed data', () {
    for (final change in <Map<String, Object?>>[
      {'role': 'owner'},
      {'accessRevision': 0},
      {'recipientId': 'stranger'},
      {'password': 'secret'},
    ]) {
      final encoded = LocalSyncStateCodec.encode(
        LocalSyncState(
          accountUserId: 'actor',
          notes: [note('owner', grant: share)],
        ),
      );
      final record = (encoded['notes'] as List).single as Map;
      (record['share'] as Map).addAll(change);
      expect(
        () => LocalSyncStateCodec.decode(encoded),
        throwsA(isA<LocalSyncCodecException>()),
      );
    }
  });
}
