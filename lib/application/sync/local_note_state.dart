/// Locally persisted state of one note.
library;

import 'note_sync_status.dart';
import '../../domain/notes/attachment.dart';
import '../../domain/notes/note_protection.dart';
import '../../domain/notes/note_identity.dart';
import '../../domain/notes/note_share_grant.dart';

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
    this.protection = const NoteProtection.unprotected(),
    this.contentAvailable = true,
    this.share,
    Iterable<Attachment> attachments = const [],
  }) : id = _requireNonBlank(id, 'id'),
       attachments = freezeAttachments(attachments, noteId: id),
       ownerId = _requireNonBlank(ownerId, 'ownerId'),
       serverRevision = _requireNonNegative(serverRevision, 'serverRevision') {
    if (share != null && share!.note != identity) {
      throw ArgumentError('Share must match canonical note identity.');
    }
    if (!contentAvailable &&
        (title.isNotEmpty ||
            content.isNotEmpty ||
            this.attachments.isNotEmpty)) {
      throw ArgumentError('Unavailable content must be redacted.');
    }
  }

  /// The identity of this note.
  final String id;
  final NoteShareGrant? share;
  NoteIdentity get identity => NoteIdentity(ownerId, id);
  String referenceFor(String actorId) => identity.referenceFor(actorId);

  /// The canonical owner, independent of the actor/account store namespace.
  final String ownerId;

  /// The current title.
  final String title;

  /// The current content.
  final String content;
  final List<Attachment> attachments;
  final NoteProtection protection;
  final bool contentAvailable;

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
        sameAttachments(other.attachments, attachments) &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.pinnedAt == pinnedAt &&
        other.serverRevision == serverRevision &&
        other.deletedAt == deletedAt &&
        other.status == status &&
        other.protection == protection &&
        other.contentAvailable == contentAvailable &&
        other.share == share;
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    title,
    content,
    Object.hashAll(attachments),
    createdAt,
    updatedAt,
    pinnedAt,
    serverRevision,
    deletedAt,
    status,
    protection,
    contentAvailable,
    share,
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
