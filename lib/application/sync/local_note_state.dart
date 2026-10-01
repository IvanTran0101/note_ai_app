/// Locally persisted state of one note.
library;

import 'note_sync_status.dart';

/// Immutable local projection of one note plus its sync bookkeeping.
///
/// [serverRevision] is the last revision the server acknowledged; it is 0 until
/// the first push applies, and it is never negative. A local tombstone is
/// represented by a non-null [deletedAt], mirroring the remote snapshot:
/// deletion is state, not absence.
final class LocalNoteState {
  /// Creates a validated local note state.
  LocalNoteState({
    required String id,
    required String ownerId,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.pinnedAt,
    int serverRevision = 0,
    this.deletedAt,
    this.status = NoteSyncStatus.synced,
  }) : id = _requireNonBlank(id, 'id'),
       ownerId = _requireNonBlank(ownerId, 'ownerId'),
       serverRevision = _requireNonNegative(serverRevision, 'serverRevision');

  /// The identity of this note.
  final String id;

  /// The account this note belongs to. Always the owning account of the store
  /// that holds it.
  final String ownerId;

  /// The current title.
  final String title;

  /// The current content.
  final String content;

  /// When the note was created locally or remotely.
  final DateTime createdAt;

  /// When the note content last changed, locally or remotely.
  final DateTime updatedAt;

  /// Owner pin time, or null when the note is unpinned.
  final DateTime? pinnedAt;

  /// The last revision acknowledged by the server; 0 before the first apply.
  final int serverRevision;

  /// When the note was deleted, or null while it is live.
  final DateTime? deletedAt;

  /// Local sync standing of this note.
  final NoteSyncStatus status;

  /// True when this note is a tombstone awaiting remote cleanup policy.
  bool get isDeleted => deletedAt != null;

  @override
  bool operator ==(Object other) {
    return other is LocalNoteState &&
        other.id == id &&
        other.ownerId == ownerId &&
        other.title == title &&
        other.content == content &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.pinnedAt == pinnedAt &&
        other.serverRevision == serverRevision &&
        other.deletedAt == deletedAt &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    title,
    content,
    createdAt,
    updatedAt,
    pinnedAt,
    serverRevision,
    deletedAt,
    status,
  );

  @override
  String toString() {
    return 'LocalNoteState(id: $id, ownerId: $ownerId, '
        'serverRevision: $serverRevision, isDeleted: $isDeleted, '
        'status: ${status.name})';
  }
}

String _requireNonBlank(String value, String fieldName) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, fieldName, 'must not be blank');
  }
  return value;
}

int _requireNonNegative(int value, String fieldName) {
  if (value < 0) {
    throw ArgumentError.value(value, fieldName, 'must not be negative');
  }
  return value;
}
