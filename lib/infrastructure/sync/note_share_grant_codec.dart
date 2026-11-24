import '../../domain/notes/note_identity.dart';
import '../../domain/notes/note_role.dart';
import '../../domain/notes/note_share_grant.dart';
import 'local_sync_codec_reader.dart';
import 'local_sync_codec_schema.dart';

/// Strict persistence mapping; email and unlock capabilities have no fields.
abstract final class NoteShareGrantCodec {
  static const fields = {
    'ownerId',
    'noteId',
    'recipientId',
    'role',
    'sharedAt',
    'updatedAt',
    'revokedAt',
    'accessRevision',
    'status',
    'sharerLabel',
  };

  static Map<String, Object?> encode(NoteShareGrant share) => {
    'ownerId': share.note.ownerId,
    'noteId': share.note.noteId,
    'recipientId': share.recipientId,
    'role': share.role.name,
    'sharedAt': share.sharedAt.toIso8601String(),
    'updatedAt': share.updatedAt.toIso8601String(),
    'revokedAt': share.revokedAt?.toIso8601String(),
    'accessRevision': share.accessRevision,
    'status': share.status.name,
    'sharerLabel': share.sharerLabel,
  };

  static NoteShareGrant? decodeOptional(SyncCodecObject parent) {
    final record = parent.requireNullableObject(LocalSyncSchema.share, fields);
    return record == null ? null : decodeRecord(record);
  }

  static NoteShareGrant decodeRecord(SyncCodecObject record) => buildCodecModel(
    () => NoteShareGrant(
      note: NoteIdentity(
        record.requireNonBlankString('ownerId'),
        record.requireNonBlankString('noteId'),
      ),
      recipientId: record.requireNonBlankString('recipientId'),
      role: record.requireEnum('role', NoteRole.values),
      sharedAt: record.requireTimestamp('sharedAt'),
      updatedAt: record.requireTimestamp('updatedAt'),
      revokedAt: record.requireNullableTimestamp('revokedAt'),
      accessRevision: record.requirePositiveInt('accessRevision'),
      status: record.requireEnum('status', NoteShareStatus.values),
      sharerLabel: record.rawValue('sharerLabel') == null
          ? null
          : record.requireString('sharerLabel'),
    ),
    path: record.path,
  );
}
