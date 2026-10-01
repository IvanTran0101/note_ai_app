part of 'note_repository.dart';

extension _NoteRepositoryAccess on NoteRepository {
  ({String account, int session, int access}) _captureWrite() => (
    account: _requireActiveAccountUserId(),
    session: sessionGeneration?.call() ?? 0,
    access: accessGuard?.accessGeneration ?? 0,
  );

  void _requireWrite(({String account, int session, int access}) context) {
    if (_requireActiveAccountUserId() != context.account ||
        (sessionGeneration?.call() ?? 0) != context.session) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
    if ((accessGuard?.accessGeneration ?? 0) != context.access) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
    }
  }

  void _requireNoteAccess(
    String id,
    String owner,
    NoteProtection p,
    NoteOperation op,
  ) {
    if (!p.enabled) return;
    final guard = accessGuard;
    if (guard == null) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
    }
    guard.requireAccess(
      ownerId: owner,
      noteId: id,
      protection: p,
      operation: op,
    );
  }
}
