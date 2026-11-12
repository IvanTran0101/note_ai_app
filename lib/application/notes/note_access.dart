import '../../domain/notes/note_protection.dart';

/// Application authority boundary. Neither UI nor Domain receives a raw grant.
abstract interface class INoteAccessGuard {
  bool allows({
    required String ownerId,
    required String noteId,
    required NoteProtection protection,
    required NoteOperation operation,
  });

  void requireAccess({
    required String ownerId,
    required String noteId,
    required NoteProtection protection,
    required NoteOperation operation,
  });

  int get accessGeneration;
}

enum NoteSecurityFailureCode {
  locked,
  unavailable,
  invalidPassword,
  invalidInput,
  denied,
  expired,
  staleRevision,
  network,
  storage,
  sessionChanged,
  pendingSync,
  recoveryUnavailable,
  invalidChallenge,
  rateLimited,
  recoveryCiphertextRetained,
}

final class NoteSecurityFailure implements Exception {
  const NoteSecurityFailure(this.code);
  final NoteSecurityFailureCode code;

  @override
  String toString() => 'NoteSecurityFailure(${code.name})';
}

final class NoteAccessCapabilities {
  const NoteAccessCapabilities({
    this.canRead = false,
    this.canEdit = false,
    this.canDelete = false,
    this.canManage = false,
    this.canSummarize = false,
    this.canExport = false,
  });

  final bool canRead;
  final bool canEdit;
  final bool canDelete;
  final bool canManage;
  final bool canSummarize;
  final bool canExport;
}
