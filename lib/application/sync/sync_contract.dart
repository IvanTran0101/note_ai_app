/// Provider-neutral contract for the remote note sync boundary (M1.0).
///
/// This library defines data exchanged by Application and Infrastructure. It
/// does not know about HTTP, AWS, JSON, local storage, or authentication SDKs.
library;

/// Mutation accepted by the remote note API.
enum SyncMutationOperation { create, update, delete }

/// Client-owned fields sent for a create or update.
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

/// One outbox mutation sent to the remote API.
final class SyncMutation {
  SyncMutation._({
    required this.mutationId,
    required this.noteId,
    required this.operation,
    required this.baseRevision,
    required this.payload,
  });

  factory SyncMutation({
    required String mutationId,
    required String noteId,
    required SyncMutationOperation operation,
    required int baseRevision,
    SyncNotePayload? payload,
  }) {
    _requireNonBlank(mutationId, 'mutationId');
    _requireNonBlank(noteId, 'noteId');
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
    );
  }

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
        other.payload == payload;
  }

  @override
  int get hashCode =>
      Object.hash(mutationId, noteId, operation, baseRevision, payload);
}

/// Server-owned note state returned by the remote API.
final class SyncNoteSnapshot {
  SyncNoteSnapshot({
    required String id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.serverUpdatedAt,
    required int revision,
    this.deletedAt,
  }) : id = _requireNonBlank(id, 'id'),
       revision = _requirePositive(revision, 'revision');

  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime serverUpdatedAt;
  final int revision;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  @override
  bool operator ==(Object other) {
    return other is SyncNoteSnapshot &&
        other.id == id &&
        other.title == title &&
        other.content == content &&
        other.createdAt == createdAt &&
        other.serverUpdatedAt == serverUpdatedAt &&
        other.revision == revision &&
        other.deletedAt == deletedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    content,
    createdAt,
    serverUpdatedAt,
    revision,
    deletedAt,
  );
}

enum SyncMutationResultStatus { applied, conflict }

/// Result of one remote mutation.
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

/// A page from the remote change feed.
final class SyncChangesPage {
  SyncChangesPage({
    required Iterable<SyncNoteSnapshot> snapshots,
    String? nextCursor,
    this.hasMore = false,
  }) : snapshots = List<SyncNoteSnapshot>.unmodifiable(snapshots),
       nextCursor = _normalizeCursor(nextCursor) {
    if (hasMore && this.nextCursor == null) {
      throw ArgumentError('hasMore requires a nextCursor');
    }
  }

  final List<SyncNoteSnapshot> snapshots;
  final String? nextCursor;
  final bool hasMore;
}

/// Provider-neutral categories for a failed remote sync call.
enum SyncErrorCode {
  networkUnavailable,
  timeout,
  serverUnavailable,
  throttled,
  unauthorized,
  forbidden,
  invalidMutation,
  unexpected,
}

/// Safe failure value for the remote sync boundary.
final class SyncFailure implements Exception {
  const SyncFailure({required this.code, this.detail});

  final SyncErrorCode code;
  final String? detail;

  bool get retryable {
    return switch (code) {
      SyncErrorCode.networkUnavailable ||
      SyncErrorCode.timeout ||
      SyncErrorCode.serverUnavailable ||
      SyncErrorCode.throttled => true,
      _ => false,
    };
  }

  @override
  String toString() => 'SyncFailure(${code.name})';
}

/// Application port implemented by the HTTP/Lambda infrastructure adapter.
abstract interface class IRemoteNoteDataSource {
  Future<SyncMutationResult> push(SyncMutation mutation);

  Future<SyncChangesPage> pull({String? cursor, int limit = 50});
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
