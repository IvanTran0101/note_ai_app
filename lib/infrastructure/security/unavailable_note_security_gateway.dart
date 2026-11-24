import '../../application/notes/note_access.dart';
import '../../application/notes/note_security_gateway.dart';
import '../../application/sync/sync_snapshot.dart';
import '../../domain/notes/note_protection.dart';

/// Offline vault access remains usable; no server capability can be invented.
final class UnavailableNoteSecurityGateway implements INoteSecurityGateway {
  const UnavailableNoteSecurityGateway();
  Never _fail() =>
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
  @override
  bool hasAuthority(String id, NoteProtection p, NoteOperation op) => false;
  @override
  void invalidate(String? id) {}
  @override
  Future<NoteProtection> metadata(String id) async => _fail();
  @override
  Future<SyncNoteSnapshot> content(String id) async => _fail();
  @override
  Future<NoteProtection> enable(String id, String p, int r) async => _fail();
  @override
  Future<NoteUnlockLease> unlock(
    String id,
    String p,
    Set<NoteOperation> ops,
  ) async => _fail();
  @override
  Future<NoteProtection> change(String id, String p, String n, int r) async =>
      _fail();
  @override
  Future<NoteProtection> disable(String id, String p, int r) async => _fail();
  @override
  Future<NoteRecoveryChallenge> requestRecovery(String id) async => _fail();
  @override
  Future<NoteUnlockLease> confirmRecovery(
    String id,
    String c,
    String code,
    String p,
  ) async => _fail();
}
