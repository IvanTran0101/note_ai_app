/// Codec for one remote note snapshot inside a conflict record (M2.0).
library;

import '../../application/sync/sync_snapshot.dart';
import 'local_sync_codec_reader.dart';
import 'local_sync_codec_schema.dart';

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
      LocalSyncSchema.id: snapshot.id,
      LocalSyncSchema.title: snapshot.title,
      LocalSyncSchema.content: snapshot.content,
      LocalSyncSchema.createdAt: snapshot.createdAt.toIso8601String(),
      LocalSyncSchema.serverUpdatedAt: snapshot.serverUpdatedAt
          .toIso8601String(),
      LocalSyncSchema.revision: snapshot.revision,
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
    final DateTime? deletedAt = record.requireNullableTimestamp(
      LocalSyncSchema.deletedAt,
    );
    return buildCodecModel(
      () => SyncNoteSnapshot(
        id: id,
        title: title,
        content: content,
        createdAt: createdAt,
        serverUpdatedAt: serverUpdatedAt,
        revision: revision,
        deletedAt: deletedAt,
      ),
      path: record.path,
    );
  }
}
