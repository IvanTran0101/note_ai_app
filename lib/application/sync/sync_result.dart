/// Results returned by one remote mutation.
library;

import 'sync_snapshot.dart';
import '../labels/local_label_state.dart';

enum SyncMutationResultStatus { applied, conflict }

final class SyncMutationResult {
  const SyncMutationResult._({
    required this.mutationId,
    required this.status,
    this.note,
    this.conflictRemote,
    this.label,
    this.labelRemote,
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
  final LocalLabelState? label;
  final LocalLabelState? labelRemote;
  factory SyncMutationResult.labelApplied({
    required String mutationId,
    required LocalLabelState label,
  }) => SyncMutationResult._(
    mutationId: _requireNonBlank(mutationId, 'mutationId'),
    status: SyncMutationResultStatus.applied,
    label: label,
  );
  factory SyncMutationResult.labelConflict({
    required String mutationId,
    LocalLabelState? remote,
  }) => SyncMutationResult._(
    mutationId: _requireNonBlank(mutationId, 'mutationId'),
    status: SyncMutationResultStatus.conflict,
    labelRemote: remote,
  );

  bool get isApplied => status == SyncMutationResultStatus.applied;
  bool get isConflict => status == SyncMutationResultStatus.conflict;
}

String _requireNonBlank(String value, String fieldName) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, fieldName, 'must not be blank');
  }
  return value;
}
