import '../../domain/notes/note_identity.dart';
import '../../domain/notes/note_role.dart';
import '../../domain/notes/note_share_grant.dart';

enum ShareFailureCode {
  unavailable,
  network,
  denied,
  recipientUnavailable,
  duplicate,
  selfShare,
  staleAccess,
  limit,
  invalidInput,
  pendingSync,
  sessionChanged,
}

final class ShareFailure implements Exception {
  const ShareFailure(this.code);
  final ShareFailureCode code;
  @override
  String toString() => 'ShareFailure(${code.name})';
}

final class ShareCommand {
  const ShareCommand({
    required this.requestId,
    required this.action,
    required this.expectedAccessRevision,
    this.email,
    this.recipientId,
    this.role,
  });
  final String requestId;
  final String action;
  final int expectedAccessRevision;
  final String? email, recipientId;
  final NoteRole? role;
}

abstract interface class ISharingGateway {
  Future<List<NoteShareGrant>> list(NoteIdentity note);
  Future<NoteShareGrant> apply(NoteIdentity note, ShareCommand command);
}
