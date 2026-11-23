import '../../domain/notes/note_identity.dart';
import '../../domain/notes/note_role.dart';
import '../../domain/notes/note_share_grant.dart';
import 'note_application.dart';
import 'sharing_gateway.dart';

/// Note edits use the existing local outbox. ACL becomes active only on server ACK.
final class NoteSharingAppService {
  NoteSharingAppService({
    required this.notes,
    required this.gateway,
    required this.generateRequestId,
    required this.sessionGeneration,
  });
  final NoteApplicationService notes;
  final ISharingGateway gateway;
  final String Function() generateRequestId;
  final int Function() sessionGeneration;
  Future<NoteDto> _owner(NoteIdentity identity) async {
    final actor = notes.currentUser.requiredUserId;
    if (identity.ownerId != actor) {
      throw const ShareFailure(ShareFailureCode.denied);
    }
    final note = await notes.readNote(identity.referenceFor(actor));
    if (!notes.capabilitiesFor(note).canManage) {
      throw const ShareFailure(ShareFailureCode.denied);
    }
    if (note.contentRevision < 1) {
      throw const ShareFailure(ShareFailureCode.pendingSync);
    }
    return note;
  }

  Future<T> _run<T>(NoteIdentity identity, Future<T> Function() request) async {
    final actor = notes.currentUser.requiredUserId,
        generation = sessionGeneration();
    await _owner(identity);
    final result = await request();
    if (notes.currentUser.userId != actor ||
        generation != sessionGeneration()) {
      throw const ShareFailure(ShareFailureCode.sessionChanged);
    }
    await _owner(identity);
    return result;
  }

  Future<List<NoteShareGrant>> list(NoteIdentity identity) =>
      _run(identity, () => gateway.list(identity));
  ShareCommand create(
    String email,
    NoteRole role, {
    int expectedAccessRevision = 0,
  }) {
    final normalized = email.trim().toLowerCase();
    if (normalized.length > 254 ||
        !RegExp(r'^[^\s@"\\]+@[^\s@"\\]+\.[^\s@"\\]+$').hasMatch(normalized)) {
      throw const ShareFailure(ShareFailureCode.invalidInput);
    }
    return ShareCommand(
      requestId: generateRequestId(),
      action: 'create',
      email: normalized,
      role: role,
      expectedAccessRevision: expectedAccessRevision,
    );
  }

  ShareCommand change(NoteShareGrant grant, NoteRole? role) => ShareCommand(
    requestId: generateRequestId(),
    action: role == null ? 'revoke' : 'role',
    recipientId: grant.recipientId,
    role: role,
    expectedAccessRevision: grant.accessRevision,
  );
  Future<NoteShareGrant> apply(NoteIdentity identity, ShareCommand command) =>
      _run(identity, () => gateway.apply(identity, command));
}
