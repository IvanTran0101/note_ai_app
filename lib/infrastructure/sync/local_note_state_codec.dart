/// Codec for one persisted local note record (M2.0).
library;

import '../../application/sync/local_note_state.dart';
import '../../application/sync/note_sync_status.dart';
import '../../domain/notes/note_protection.dart';
import 'local_sync_codec_reader.dart';
import 'local_sync_codec_schema.dart';
import 'note_share_grant_codec.dart';

/// Maps a [LocalNoteState] to and from one stored record.
///
/// Every field is written, including the tombstone marker ([LocalNoteState
/// .deletedAt]) and the local sync status. Nullable fields are explicit nulls,
/// so the record shape never depends on whether a note is live.
abstract final class LocalNoteStateCodec {
  /// Encodes [note] as a JSON-compatible object.
  static Map<String, Object?> encode(LocalNoteState note) {
    return <String, Object?>{
      LocalSyncSchema.protected: note.protection.enabled,
      LocalSyncSchema.protectionRevision: note.protection.revision,
      LocalSyncSchema.contentAvailable: note.contentAvailable,
      LocalSyncSchema.id: note.id,
      LocalSyncSchema.ownerId: note.ownerId,
      LocalSyncSchema.title: note.title,
      LocalSyncSchema.content: note.content,
      LocalSyncSchema.createdAt: note.createdAt.toIso8601String(),
      LocalSyncSchema.updatedAt: note.updatedAt.toIso8601String(),
      LocalSyncSchema.serverRevision: note.serverRevision,
      LocalSyncSchema.deletedAt: note.deletedAt?.toIso8601String(),
      LocalSyncSchema.status: note.status.name,
      if (note.share != null)
        LocalSyncSchema.share: NoteShareGrantCodec.encode(note.share!),
    };
  }

  /// Decodes one standalone note record.
  static LocalNoteState decode(Object? data, {String path = 'note'}) {
    return decodeRecord(
      SyncCodecObject.from(
        data,
        path: path,
        allowedFields: LocalSyncSchema.noteFields,
        optionalFields: LocalSyncSchema.noteOptionalFields,
      ),
    );
  }

  /// Decodes a note record already wrapped by the envelope or a conflict.
  static LocalNoteState decodeRecord(SyncCodecObject record) {
    final String id = record.requireNonBlankString(LocalSyncSchema.id);
    final String ownerId = record.requireNonBlankString(
      LocalSyncSchema.ownerId,
    );
    final String title = record.requireString(LocalSyncSchema.title);
    final String content = record.requireString(LocalSyncSchema.content);
    final DateTime createdAt = record.requireTimestamp(
      LocalSyncSchema.createdAt,
    );
    final DateTime updatedAt = record.requireTimestamp(
      LocalSyncSchema.updatedAt,
    );
    final int serverRevision = record.requireNonNegativeInt(
      LocalSyncSchema.serverRevision,
    );
    final DateTime? deletedAt = record.requireNullableTimestamp(
      LocalSyncSchema.deletedAt,
    );
    final NoteSyncStatus status = record.requireEnum(
      LocalSyncSchema.status,
      NoteSyncStatus.values,
    );
    return buildCodecModel(
      () => LocalNoteState(
        id: id,
        ownerId: ownerId,
        share: NoteShareGrantCodec.decodeOptional(record),
        title: title,
        content: content,
        createdAt: createdAt,
        updatedAt: updatedAt,
        serverRevision: serverRevision,
        deletedAt: deletedAt,
        status: status,
        protection: NoteProtection(
          enabled: record.requireBool(LocalSyncSchema.protected),
          revision: record.requireNonNegativeInt(
            LocalSyncSchema.protectionRevision,
          ),
        ),
        contentAvailable: record.requireBool(LocalSyncSchema.contentAvailable),
      ),
      path: record.path,
    );
  }
}
