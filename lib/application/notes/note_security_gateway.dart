import '../../domain/notes/note_protection.dart';
import '../sync/sync_snapshot.dart';

/// Safe proof facts. Raw transport credentials remain private to Infrastructure.
final class NoteUnlockLease {
  NoteUnlockLease({
    required this.protection,
    required Iterable<NoteOperation> operations,
    required this.expiresAt,
  }) : operations = Set<NoteOperation>.unmodifiable(operations);
  final NoteProtection protection;
  final Set<NoteOperation> operations;
  final DateTime expiresAt;
}

final class NoteRecoveryChallenge {
  const NoteRecoveryChallenge(this.id, this.expiresAt);
  final String id;
  final DateTime expiresAt;
}

abstract interface class INoteSecurityGateway {
  Future<NoteProtection> metadata(String noteId);
  Future<SyncNoteSnapshot> content(String noteId);
  Future<NoteProtection> enable(
    String noteId,
    String password,
    int contentRevision,
  );
  Future<NoteUnlockLease> unlock(
    String noteId,
    String password,
    Set<NoteOperation> operations,
  );
  Future<NoteProtection> change(
    String noteId,
    String currentPassword,
    String newPassword,
    int epoch,
  );
  Future<NoteProtection> disable(
    String noteId,
    String currentPassword,
    int epoch,
  );
  Future<NoteRecoveryChallenge> requestRecovery(String noteId);
  Future<NoteUnlockLease> confirmRecovery(
    String noteId,
    String challengeId,
    String code,
    String newPassword,
  );
  bool hasAuthority(
    String noteId,
    NoteProtection protection,
    NoteOperation operation,
  );
  void invalidate(String? noteId);
}
