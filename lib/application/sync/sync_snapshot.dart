/// Server snapshots and pages from the remote note change feed.
library;

import '../../domain/notes/note_protection.dart';
import '../../domain/notes/note_identity.dart';
import '../../domain/notes/note_share_grant.dart';

final class SyncNoteSnapshot {
  SyncNoteSnapshot({
    required String id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.serverUpdatedAt,
    required int revision,
    this.deletedAt,
    this.protection = const NoteProtection.unprotected(),
    this.contentAvailable = true,
    this.ownerId,
    this.share,
  }) : id = _requireNonBlank(id, 'id'),
       revision = _requirePositive(revision, 'revision') {
    if (ownerId != null && ownerId!.trim().isEmpty ||
        share != null &&
            (ownerId == null ||
                share!.note != identityFor(ownerId!) ||
                accessRemoved &&
                    (contentAvailable ||
                        title.isNotEmpty ||
                        content.isNotEmpty))) {
      throw ArgumentError('Invalid canonical access projection.');
    }
  }

  final String id;
  final String? ownerId;
  final NoteShareGrant? share;
  NoteIdentity identityFor(String actorId) =>
      NoteIdentity(ownerId ?? actorId, id);
  bool get accessRemoved => share != null && !share!.isActive;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime serverUpdatedAt;
  final int revision;
  final DateTime? deletedAt;
  final NoteProtection protection;
  final bool contentAvailable;

  bool get isDeleted => deletedAt != null;

  @override
  bool operator ==(Object other) {
    return other is SyncNoteSnapshot &&
        other.id == id &&
        other.title == title &&
        other.content == content &&
        other.createdAt == createdAt &&
        other.serverUpdatedAt == serverUpdatedAt &&
        other.revision == revision &&
        other.deletedAt == deletedAt &&
        other.protection == protection &&
        other.contentAvailable == contentAvailable &&
        other.ownerId == ownerId &&
        other.share == share;
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    content,
    createdAt,
    serverUpdatedAt,
    revision,
    deletedAt,
    protection,
    contentAvailable,
    ownerId,
    share,
  );
}

final class SyncChangesPage {
  SyncChangesPage({
    required Iterable<SyncNoteSnapshot> snapshots,
    String? nextCursor,
    this.hasMore = false,
  }) : snapshots = List<SyncNoteSnapshot>.unmodifiable(snapshots),
       nextCursor = _normalizeCursor(nextCursor) {
    if (hasMore && this.nextCursor == null) {
      throw ArgumentError('hasMore requires a nextCursor');
    }
  }

  final List<SyncNoteSnapshot> snapshots;
  final String? nextCursor;
  final bool hasMore;
}

String _requireNonBlank(String value, String fieldName) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, fieldName, 'must not be blank');
  }
  return value;
}

int _requirePositive(int value, String fieldName) {
  if (value <= 0) {
    throw ArgumentError.value(value, fieldName, 'must be positive');
  }
  return value;
}

String? _normalizeCursor(String? value) {
  return value == null || value.isEmpty ? null : value;
}
