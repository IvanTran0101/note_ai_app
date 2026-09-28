/// Server snapshots and pages from the remote note change feed.
library;

final class SyncNoteSnapshot {
  SyncNoteSnapshot({
    required String id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.serverUpdatedAt,
    required int revision,
    this.deletedAt,
  }) : id = _requireNonBlank(id, 'id'),
       revision = _requirePositive(revision, 'revision');

  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime serverUpdatedAt;
  final int revision;
  final DateTime? deletedAt;

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
        other.deletedAt == deletedAt;
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
