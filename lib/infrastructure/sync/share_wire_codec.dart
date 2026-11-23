import '../../domain/notes/note_identity.dart';
import '../../domain/notes/note_role.dart';
import '../../domain/notes/note_share_grant.dart';

/// Shared server DTOs have no email, passwords or capabilities.
abstract final class ShareWireCodec {
  static NoteShareGrant decode(Object? value) {
    try {
      final m = Map<String, Object?>.from(value as Map);
      const fields = {
        'ownerId',
        'noteId',
        'recipientId',
        'role',
        'accessRevision',
        'status',
        'sharedAt',
        'updatedAt',
        'revokedAt',
        'sharerLabel',
      };
      if (m.keys.any((k) => !fields.contains(k))) throw const FormatException();
      DateTime timestamp(String key) =>
          DateTime.parse(m[key] as String).toUtc();
      return NoteShareGrant(
        note: NoteIdentity(m['ownerId'] as String, m['noteId'] as String),
        recipientId: m['recipientId'] as String,
        role: NoteRole.values.byName(m['role'] as String),
        accessRevision: m['accessRevision'] as int,
        status: NoteShareStatus.values.byName(m['status'] as String),
        sharedAt: timestamp('sharedAt'),
        updatedAt: timestamp('updatedAt'),
        revokedAt: m['revokedAt'] == null ? null : timestamp('revokedAt'),
        sharerLabel: m['sharerLabel'] as String?,
      );
    } on Object {
      throw const FormatException('Invalid share metadata.');
    }
  }
}
