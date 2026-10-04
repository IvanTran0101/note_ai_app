/// Server snapshots and pages from the remote note change feed.
library;

import '../../domain/labels/label.dart';
import '../../domain/labels/label_projection.dart';
import '../labels/local_label_state.dart';

import '../../domain/notes/note_protection.dart';
import '../../domain/notes/attachment.dart';
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
    this.pinnedAt,
    this.deletedAt,
    this.protection = const NoteProtection.unprotected(),
    this.contentAvailable = true,
    this.ownerId,
    this.share,
    Iterable<Attachment> attachments = const [],
    bool? includesAttachments,
    Iterable<String> labelIds = const [],
    Iterable<LabelProjection> labelProjections = const [],
    this.includesLabels = false,
  }) : id = _requireNonBlank(id, 'id'),
       includesAttachments = includesAttachments ?? attachments.isNotEmpty,
       attachments = freezeAttachments(attachments, noteId: id),
       labelIds = freezeLabelIds(labelIds),
       labelProjections = List.unmodifiable(labelProjections),
       revision = _requirePositive(revision, 'revision') {
    if (ownerId != null && ownerId!.trim().isEmpty ||
        share != null &&
            (ownerId == null ||
                share!.note != identityFor(ownerId!) ||
                accessRemoved &&
                    (contentAvailable ||
                        title.isNotEmpty ||
                        content.isNotEmpty ||
                        this.attachments.isNotEmpty))) {
      throw ArgumentError('Invalid canonical access projection.');
    }
    if (!contentAvailable &&
        (title.isNotEmpty ||
            content.isNotEmpty ||
            this.attachments.isNotEmpty ||
            this.labelIds.isNotEmpty ||
            this.labelProjections.isNotEmpty)) {
      throw ArgumentError('Unavailable snapshot must be redacted.');
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
  final List<Attachment> attachments;
  final List<String> labelIds;
  final List<LabelProjection> labelProjections;
  final bool includesLabels;
  final bool includesAttachments;
  final DateTime createdAt;
  final DateTime serverUpdatedAt;
  final int revision;
  final DateTime? pinnedAt;
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
        sameAttachments(other.attachments, attachments) &&
        other.includesAttachments == includesAttachments &&
        sameLabelIds(other.labelIds, labelIds) &&
        other.includesLabels == includesLabels &&
        _sameLabels(other.labelProjections, labelProjections) &&
        other.createdAt == createdAt &&
        other.serverUpdatedAt == serverUpdatedAt &&
        other.revision == revision &&
        other.pinnedAt == pinnedAt &&
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
    Object.hashAll(attachments),
    includesAttachments,
    createdAt,
    serverUpdatedAt,
    revision,
    pinnedAt,
    deletedAt,
    protection,
    contentAvailable,
    ownerId,
    share,
    Object.hashAll(labelIds),
    Object.hashAll(labelProjections),
    includesLabels,
  );
}

final class SyncChangesPage {
  SyncChangesPage({
    required Iterable<SyncNoteSnapshot> snapshots,
    String? nextCursor,
    this.hasMore = false,
    this.catchUpPending = false,
    Iterable<LocalLabelState> labels = const [],
    this.wireVersion = 1,
  }) : snapshots = List<SyncNoteSnapshot>.unmodifiable(snapshots),
       labels = List.unmodifiable(labels),
       nextCursor = _normalizeCursor(nextCursor) {
    if (hasMore && this.nextCursor == null) {
      throw ArgumentError('hasMore requires a nextCursor');
    }
  }

  final List<SyncNoteSnapshot> snapshots;
  final List<LocalLabelState> labels;
  final int wireVersion;
  final String? nextCursor;
  final bool hasMore;
  final bool catchUpPending;
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

bool _sameLabels(List<LabelProjection> a, List<LabelProjection> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);
