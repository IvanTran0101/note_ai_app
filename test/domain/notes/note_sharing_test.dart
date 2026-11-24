import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_access_policy.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/domain/notes/note_role.dart';
import 'package:note_ai_app/domain/notes/note_share_grant.dart';

void main() {
  final at = DateTime.utc(2026, 10, 2);
  NoteShareGrant grant(NoteRole role) => NoteShareGrant(
    note: NoteIdentity('owner', 'same'),
    recipientId: 'recipient',
    role: role,
    sharedAt: at,
    updatedAt: at,
    accessRevision: 1,
  );
  test('canonical references survive delimiters, Unicode and reserved ids', () {
    for (final owner in ['owner', 'abc:3:def', '👥 chủ']) {
      for (final id in ['same', 'nf-note:owned', '4:😺:1']) {
        final pair = NoteIdentity(owner, id);
        expect(NoteIdentity.resolve(pair.referenceFor('actor'), 'actor'), pair);
        expect(NoteIdentity.resolve(pair.referenceFor(owner), owner), pair);
      }
    }
    expect(NoteIdentity('a', 'same'), isNot(NoteIdentity('b', 'same')));
    expect(NoteIdentity('a', 'bc').key, isNot(NoteIdentity('ab', 'c').key));
  });
  test('malformed canonical references cannot fall back to owned ids', () {
    for (final value in [
      'nf-note:',
      'nf-note:0:a1:b',
      'nf-note:01:a1:b',
      'nf-note:1:a1:bextra',
      'nf-note:999:a',
    ]) {
      expect(() => NoteIdentity.resolve(value, 'actor'), throwsFormatException);
    }
  });
  test('only owner can change, revoke and explicitly reactivate shares', () {
    final active = grant(NoteRole.editor);
    expect(() => active.revoke('recipient', at), throwsStateError);
    final viewer = active.changeRole('owner', NoteRole.viewer, at);
    final revoked = viewer.revoke('owner', at);
    expect(revoked.accessRevision, 3);
    expect(revoked.revokedAt, at);
    expect(
      () => revoked.changeRole('owner', NoteRole.editor, at),
      throwsStateError,
    );
    final reshared = revoked.reactivate('owner', NoteRole.editor, at);
    expect(reshared.isActive, true);
    expect(reshared.accessRevision, 4);
    expect(reshared.sharedAt, active.sharedAt);
    expect(reshared.revokedAt, null);
  });
  test('self-share and time/revision rollback are rejected', () {
    expect(
      () => NoteShareGrant(
        note: NoteIdentity('owner', 'n'),
        recipientId: 'owner',
        role: NoteRole.viewer,
        sharedAt: at,
        updatedAt: at,
        accessRevision: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () =>
          grant(NoteRole.editor)
              .revoke('owner', at.subtract(const Duration(seconds: 1))),
      throwsArgumentError,
    );
  });
  test('viewer and editor have exactly their allowed business operations', () {
    const policy = NoteAccessPolicy();
    for (final role in NoteRole.values) {
      final share = grant(role);
      for (final op in NoteOperation.values) {
        final allowed = {
          NoteOperation.read,
          NoteOperation.summary,
          NoteOperation.attachmentRead,
          if (role == NoteRole.editor) NoteOperation.edit,
        };
        expect(
          policy.allows(
            actorId: 'recipient',
            note: share.note,
            operation: op,
            share: share,
          ),
          allowed.contains(op),
          reason: '$role/$op',
        );
        expect(
          policy.allows(
            actorId: 'stranger',
            note: share.note,
            operation: op,
            share: share,
          ),
          false,
        );
        expect(
          policy.allows(actorId: 'owner', note: share.note, operation: op),
          true,
        );
      }
      expect(
        policy.allows(
          actorId: 'recipient',
          note: NoteIdentity('other', 'same'),
          operation: NoteOperation.read,
          share: share,
        ),
        false,
      );
      expect(
        policy.allows(
          actorId: 'recipient',
          note: share.note,
          operation: NoteOperation.read,
          share: share.revoke('owner', at),
        ),
        false,
      );
    }
  });
}
