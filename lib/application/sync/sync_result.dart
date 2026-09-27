/// Results returned by one remote mutation.
library;

import 'sync_snapshot.dart';

enum SyncMutationResultStatus { applied, conflict }

final class SyncMutationResult {
  const SyncMutationResult._({
    required this.mutationId,
    required this.status,
    this.note,
    this.conflictRemote,
  });

  factory SyncMutationResult.applied({
    required String mutationId,
    required SyncNoteSnapshot note,
  }) {
    return SyncMutationResult._(
      mutationId: _requireNonBlank(mutationId, 'mutationId'),
      status: SyncMutationResultStatus.applied,
      note: note,
    );
  }

  factory SyncMutationResult.conflict({
    required String mutationId,
    SyncNoteSnapshot? remote,
  }) {
    return SyncMutationResult._(
      mutationId: _requireNonBlank(mutationId, 'mutationId'),
      status: SyncMutationResultStatus.conflict,
      conflictRemote: remote,
    );
  }

  final String mutationId;
  final SyncMutationResultStatus status;
  final SyncNoteSnapshot? note;
  final SyncNoteSnapshot? conflictRemote;

  bool get isApplied => status == SyncMutationResultStatus.applied;
  bool get isConflict => status == SyncMutationResultStatus.conflict;
}

String _requireNonBlank(String value, String fieldName) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, fieldName, 'must not be blank');
  }
  return value;
}
