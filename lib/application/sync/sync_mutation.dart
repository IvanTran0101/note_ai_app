/// Client-owned changes sent to the remote note API.
library;

import 'protection_sync_change.dart';
import '../../domain/notes/attachment.dart';

import '../../domain/notes/note_identity.dart';
import '../../domain/labels/label.dart';
import '../../domain/labels/label_membership.dart';

enum SyncEntityType { note, label }

enum SyncMutationOperation { create, update, delete }

final class SyncNotePayload {
  const SyncNotePayload({
    required this.title,
    required this.content,
    this.pinnedAt,
    this.includesPinnedAt = false,
    this.attachmentManifest = const AttachmentManifest.empty(),
    this.includesAttachments = false,
    this.labelMembership = const LabelMembership.empty(),
    this.includesLabels = false,
  });

  final String title;
  final String content;
  final AttachmentManifest attachmentManifest;
  List<Attachment> get attachments => attachmentManifest.values;
  final bool includesAttachments;
  final LabelMembership labelMembership;
  List<String> get labelIds => labelMembership.values;
  final bool includesLabels;
  final DateTime? pinnedAt;

  /// False for persisted mutations created before pin was added. Keeping that
  /// shape avoids changing the idempotency fingerprint of an attempted request.
  final bool includesPinnedAt;

  @override
  bool operator ==(Object other) {
    return other is SyncNotePayload &&
        other.title == title &&
        other.content == content &&
        other.attachmentManifest == attachmentManifest &&
        other.includesAttachments == includesAttachments &&
        other.pinnedAt == pinnedAt &&
        other.includesPinnedAt == includesPinnedAt &&
        other.labelMembership == labelMembership &&
        other.includesLabels == includesLabels;
  }

  @override
  int get hashCode => Object.hash(
    title,
    content,
    pinnedAt,
    includesPinnedAt,
    attachmentManifest,
    includesAttachments,
    labelMembership,
    includesLabels,
  );
}

final class SyncMutation {
  SyncMutation._({
    required this.mutationId,
    required this.noteId,
    required this.operation,
    required this.baseRevision,
    required this.payload,
    required this.ownerId,
    required this.accessRevision,
    required this.protectionChange,
    required this.entityType,
    required this.labelName,
  });

  factory SyncMutation({
    required String mutationId,
    required String noteId,
    required SyncMutationOperation operation,
    required int baseRevision,
    SyncNotePayload? payload,
    String? ownerId,
    int? accessRevision,
    ProtectionSyncChange? protectionChange,
    SyncEntityType entityType = SyncEntityType.note,
    String? labelName,
  }) {
    _requireNonBlank(mutationId, 'mutationId');
    _requireNonBlank(noteId, 'noteId');
    if (ownerId != null) _requireNonBlank(ownerId, 'ownerId');
    if (accessRevision != null && accessRevision <= 0) {
      throw ArgumentError('Access revision must be positive.');
    }
    if (baseRevision < 0) {
      throw ArgumentError.value(
        baseRevision,
        'baseRevision',
        'must not be negative',
      );
    }
    if (operation == SyncMutationOperation.delete && protectionChange != null) {
      throw ArgumentError('Protection changes require a content mutation.');
    }
    if (entityType == SyncEntityType.label) {
      if (ownerId != null ||
          accessRevision != null ||
          protectionChange != null ||
          payload != null) {
        throw ArgumentError('Label catalog mutations are actor-owned.');
      }
      if (operation != SyncMutationOperation.delete) {
        requireLabelName(labelName ?? '');
      }
    }
    if (entityType == SyncEntityType.note && labelName != null) {
      throw ArgumentError('Note mutations cannot carry catalog names.');
    }
    if (entityType == SyncEntityType.note &&
        operation != SyncMutationOperation.delete &&
        payload == null) {
      throw ArgumentError.value(
        payload,
        'payload',
        'is required for create and update',
      );
    }
    return SyncMutation._(
      mutationId: mutationId,
      noteId: noteId,
      operation: operation,
      baseRevision: baseRevision,
      payload: payload,
      ownerId: ownerId,
      accessRevision: accessRevision,
      protectionChange: protectionChange,
      entityType: entityType,
      labelName: labelName == null ? null : requireLabelName(labelName),
    );
  }

  final String? ownerId;
  final int? accessRevision;
  final ProtectionSyncChange? protectionChange;
  final SyncEntityType entityType;
  final String? labelName;
  bool get isLabel => entityType == SyncEntityType.label;
  String keyFor(String actorId) =>
      isLabel ? 'label:$actorId:$noteId' : identityFor(actorId).key;
  NoteIdentity identityFor(String actorId) =>
      NoteIdentity(ownerId ?? actorId, noteId);

  final String mutationId;
  final String noteId;
  final SyncMutationOperation operation;
  final int baseRevision;
  final SyncNotePayload? payload;

  @override
  bool operator ==(Object other) {
    return other is SyncMutation &&
        other.mutationId == mutationId &&
        other.noteId == noteId &&
        other.operation == operation &&
        other.baseRevision == baseRevision &&
        other.payload == payload &&
        other.ownerId == ownerId &&
        other.accessRevision == accessRevision &&
        other.protectionChange == protectionChange &&
        other.entityType == entityType &&
        other.labelName == labelName;
  }

  @override
  int get hashCode => Object.hash(
    mutationId,
    noteId,
    operation,
    baseRevision,
    payload,
    ownerId,
    accessRevision,
    protectionChange,
    entityType,
    labelName,
  );
}

String _requireNonBlank(String value, String fieldName) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, fieldName, 'must not be blank');
  }
  return value;
}
