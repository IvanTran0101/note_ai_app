/// Client-owned changes sent to the remote note API.
library;

import '../../domain/notes/note_identity.dart';

enum SyncMutationOperation { create, update, delete }

final class SyncNotePayload {
  const SyncNotePayload({required this.title, required this.content});

  final String title;
  final String content;

  @override
  bool operator ==(Object other) {
    return other is SyncNotePayload &&
        other.title == title &&
        other.content == content;
  }

  @override
  int get hashCode => Object.hash(title, content);
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
  });

  factory SyncMutation({
    required String mutationId,
    required String noteId,
    required SyncMutationOperation operation,
    required int baseRevision,
    SyncNotePayload? payload,
    String? ownerId,
    int? accessRevision,
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
    );
  }

  final String? ownerId;
  final int? accessRevision;
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
        other.accessRevision == accessRevision;
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
  );
}

String _requireNonBlank(String value, String fieldName) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, fieldName, 'must not be blank');
  }
  return value;
}
