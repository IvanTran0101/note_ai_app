part of 'note_repository.dart';

extension _NoteRepositoryMapping on NoteRepository {
  SyncNotePayload _payloadOf(
    Note note, {
    bool includePin = false,
    bool includeAttachments = false,
  }) {
    return SyncNotePayload(
      title: note.title,
      content: note.content,
      document: note.document,
      includesDocument: note.document != null,
      attachmentManifest: AttachmentManifest(note.attachments, noteId: note.id),
      labelMembership: LabelMembership(note.labelIds),
      includesLabels: labelsEnabled && note.share == null,
      includesAttachments:
          note.share == null &&
          (includeAttachments || note.attachments.isNotEmpty),
      pinnedAt: note.pinnedAt,
      includesPinnedAt:
          note.share == null && (includePin || note.pinnedAt != null),
    );
  }
}

LocalNoteState _localNoteFromDomain(
  Note note, {
  required int serverRevision,
  required NoteSyncStatus status,
}) {
  final result = LocalNoteState(
    id: note.id,
    ownerId: note.ownerId,
    title: note.title,
    content: note.content,
    document: note.document,
    createdAt: note.createdAt,
    updatedAt: note.updatedAt,
    pinnedAt: note.pinnedAt,
    serverRevision: serverRevision,
    attachments: note.attachments,
    labelIds: note.labelIds,
    labelProjections: note.labelProjections,
    status: status,
    protection: note.protection,
    contentAvailable: note.contentAvailable,
    share: note.share,
  );
  // Before any in-memory store transform or encrypted CAS may commit.
  if (result.document != null) LocalNoteStateCodec.encode(result);
  return result;
}

Note _domainNoteFromLocal(LocalNoteState note, {bool metadataOnly = false}) {
  final bool available =
      note.contentAvailable && !metadataOnly && (note.share?.isActive ?? true);
  return Note.reconstitute(
    id: note.id,
    ownerId: note.ownerId,
    title: available ? note.title : '',
    attachments: available ? note.attachments : const [],
    labelIds: available ? note.labelIds : const [],
    labelProjections: available ? note.labelProjections : const [],
    content: available ? note.content : '',
    document: available ? note.document : null,
    createdAt: note.createdAt,
    updatedAt: note.updatedAt,
    protection: note.protection,
    contentAvailable: available,
    contentRevision: note.serverRevision,
    share: note.share,
    pinnedAt: note.pinnedAt,
  );
}
