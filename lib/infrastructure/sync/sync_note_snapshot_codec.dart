/// Codec for one remote note snapshot inside a conflict record (M2.0).
library;

import '../../application/sync/sync_snapshot.dart';
import '../../domain/notes/note_protection.dart';
import 'local_sync_codec_reader.dart';
import 'local_sync_codec_schema.dart';
import 'note_share_grant_codec.dart';

/// Maps a [SyncNoteSnapshot] to and from its stored form.
///
/// A snapshot is stored only as the remote side of a conflict. Its tombstone
/// marker is explicit, so a conflicting remote deletion is distinguishable from
/// a missing remote note, which is stored as a null snapshot by the caller.
/// `revision` follows the remote contract and is positive; `serverUpdatedAt`
/// keeps the server's own field name rather than the local `updatedAt`.
abstract final class SyncNoteSnapshotCodec {
  /// Encodes [snapshot] as a JSON-compatible object.
  static Map<String, Object?> encode(SyncNoteSnapshot snapshot) {
    return <String, Object?>{
      LocalSyncSchema.protected: snapshot.protection.enabled,
      LocalSyncSchema.protectionRevision: snapshot.protection.revision,
      LocalSyncSchema.contentAvailable: snapshot.contentAvailable,
      LocalSyncSchema.id: snapshot.id,
      if (snapshot.ownerId != null) LocalSyncSchema.ownerId: snapshot.ownerId,
      if (snapshot.share != null)
        LocalSyncSchema.share: NoteShareGrantCodec.encode(snapshot.share!),
      LocalSyncSchema.title: snapshot.title,
      LocalSyncSchema.content: snapshot.content,
      LocalSyncSchema.createdAt: snapshot.createdAt.toIso8601String(),
      LocalSyncSchema.serverUpdatedAt: snapshot.serverUpdatedAt
          .toIso8601String(),
      LocalSyncSchema.revision: snapshot.revision,
      LocalSyncSchema.pinnedAt: snapshot.pinnedAt?.toIso8601String(),
      LocalSyncSchema.deletedAt: snapshot.deletedAt?.toIso8601String(),
    };
  }

  /// Decodes one standalone remote snapshot record.
  static SyncNoteSnapshot decode(Object? data, {String path = 'remote note'}) {
    return decodeRecord(
      SyncCodecObject.from(
        data,
        path: path,
        allowedFields: LocalSyncSchema.snapshotFields,
        optionalFields: LocalSyncSchema.snapshotOptionalFields,
      ),
    );
  }

  /// Decodes a snapshot record already wrapped by a conflict.
  static SyncNoteSnapshot decodeRecord(SyncCodecObject record) {
    final String id = record.requireNonBlankString(LocalSyncSchema.id);
    final String title = record.requireString(LocalSyncSchema.title);
    final String content = record.requireString(LocalSyncSchema.content);
    final DateTime createdAt = record.requireTimestamp(
      LocalSyncSchema.createdAt,
    );
    final DateTime serverUpdatedAt = record.requireTimestamp(
      LocalSyncSchema.serverUpdatedAt,
    );
    final int revision = record.requirePositiveInt(LocalSyncSchema.revision);
    final DateTime? pinnedAt = record.requireNullableTimestamp(
      LocalSyncSchema.pinnedAt,
    );
    final DateTime? deletedAt = record.requireNullableTimestamp(
      LocalSyncSchema.deletedAt,
    );
    return buildCodecModel(
      () => SyncNoteSnapshot(
        id: id,
        ownerId: !record.containsField(LocalSyncSchema.ownerId)
            ? null
            : record.requireNonBlankString(LocalSyncSchema.ownerId),
        share: NoteShareGrantCodec.decodeOptional(record),
        title: title,
        content: content,
        createdAt: createdAt,
        serverUpdatedAt: serverUpdatedAt,
        revision: revision,
        pinnedAt: pinnedAt,
        deletedAt: deletedAt,
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
