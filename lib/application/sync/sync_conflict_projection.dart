part of 'sync_conflict_resolver.dart';

/// Pure conflict snapshot copies; policy and the canonical write stay in resolver.
LocalNoteState? _findNote(LocalSyncState state, NoteIdentity identity) {
  for (final LocalNoteState note in state.notes) {
    if (note.identity == identity) return note;
  }
  return null;
}

LocalNoteState _pendingNote(
  LocalNoteState note, {
  required int serverRevision,
  NoteDocument? document,
}) => LocalNoteState(
  id: note.id,
  ownerId: note.ownerId,
  share: note.share,
  title: note.title,
  content: note.content,
  document: document ?? note.document,
  createdAt: note.createdAt,
  updatedAt: note.updatedAt,
  pinnedAt: note.pinnedAt,
  attachments: note.attachments,
  labelIds: note.labelIds,
  labelProjections: note.labelProjections,
  serverRevision: serverRevision,
  deletedAt: note.deletedAt,
  status: NoteSyncStatus.pending,
  protection: note.protection,
  contentAvailable: note.contentAvailable,
);

LocalNoteState _fromRemote(
  SyncNoteSnapshot note,
  String accountUserId, {
  LocalNoteState? previous,
}) => LocalNoteState(
  id: note.id,
  ownerId: note.ownerId ?? accountUserId,
  share: note.share,
  title: note.title,
  content: note.content,
  document: projectSyncDocument(note, previous),
  createdAt: note.createdAt,
  updatedAt: note.serverUpdatedAt,
  pinnedAt: note.pinnedAt,
  attachments: !note.contentAvailable || note.isDeleted
      ? const []
      : note.includesAttachments
      ? note.attachments
      : previous?.attachments ?? const [],
  labelIds: !note.contentAvailable || note.isDeleted
      ? const []
      : note.includesLabels
      ? note.labelIds
      : previous?.labelIds ?? const [],
  labelProjections: !note.contentAvailable || note.isDeleted
      ? const []
      : note.includesLabels
      ? note.labelProjections
      : previous?.labelProjections ?? const [],
  serverRevision: note.revision,
  deletedAt: note.deletedAt,
  status: NoteSyncStatus.synced,
  protection: note.protection,
  contentAvailable: note.contentAvailable,
);
