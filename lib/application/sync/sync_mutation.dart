/// Client-owned changes sent to the remote note API.
library;

import 'protection_sync_change.dart';
import '../../domain/notes/attachment.dart';

import '../../domain/notes/note_identity.dart';

enum SyncMutationOperation { create, update, delete }

final class SyncNotePayload {
  const SyncNotePayload({
    required this.title,
    required this.content,
    this.pinnedAt,
    this.includesPinnedAt = false,
    this.attachmentManifest = const AttachmentManifest.empty(),
    this.includesAttachments = false,
  });

  final String title;
  final String content;
  final AttachmentManifest attachmentManifest;
  List<Attachment> get attachments => attachmentManifest.values;
  final bool includesAttachments;
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
        other.includesPinnedAt == includesPinnedAt;
  }

  @override
  int get hashCode => Object.hash(
    title,
    content,
    pinnedAt,
    includesPinnedAt,
    attachmentManifest,
    includesAttachments,
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
    if (operation != SyncMutationOperation.delete && payload == null) {
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
    );
  }

  final String? ownerId;
  final int? accessRevision;
  final ProtectionSyncChange? protectionChange;
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
        other.protectionChange == protectionChange;
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
  );
}

String _requireNonBlank(String value, String fieldName) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, fieldName, 'must not be blank');
  }
  return value;
}
