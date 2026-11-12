import 'note_identity.dart';
import 'note_role.dart';

enum NoteShareStatus { active, revoked }

/// Persisted ACL snapshot. This never represents an M05 unlock capability.
final class NoteShareGrant {
  NoteShareGrant({
    required this.note,
    required this.recipientId,
    required this.role,
    required this.sharedAt,
    required this.updatedAt,
    required this.accessRevision,
    this.status = NoteShareStatus.active,
    this.revokedAt,
    this.sharerLabel,
  }) {
    if (recipientId.trim().isEmpty ||
        recipientId == note.ownerId ||
        accessRevision <= 0 ||
        updatedAt.isBefore(sharedAt) ||
        (status == NoteShareStatus.active && revokedAt != null) ||
        (status == NoteShareStatus.revoked && revokedAt == null) ||
        (revokedAt?.isBefore(sharedAt) ?? false) ||
        (revokedAt?.isAfter(updatedAt) ?? false)) {
      throw ArgumentError('Invalid sharing grant.');
    }
  }
  final NoteIdentity note;
  final String recipientId;
  final NoteRole role;
  final DateTime sharedAt;
  final DateTime updatedAt;
  final DateTime? revokedAt;
  final int accessRevision;
  final NoteShareStatus status;
  final String? sharerLabel;
  bool get isActive => status == NoteShareStatus.active;

  NoteShareGrant changeRole(String actorId, NoteRole next, DateTime now) {
    _requireOwner(actorId);
    if (!isActive) {
      throw StateError('A revoked share must be explicitly reactivated.');
    }
    return _next(role: next, now: now, active: true);
  }

  NoteShareGrant revoke(String actorId, DateTime now) {
    _requireOwner(actorId);
    if (!isActive) throw StateError('Share is already revoked.');
    return _next(role: role, now: now, active: false);
  }

  NoteShareGrant reactivate(String actorId, NoteRole next, DateTime now) {
    _requireOwner(actorId);
    if (isActive) throw StateError('Share is already active.');
    return _next(role: next, now: now, active: true);
  }

  void _requireOwner(String actorId) {
    if (actorId != note.ownerId) {
      throw StateError('Only the owner manages a share.');
    }
  }

  NoteShareGrant _next({
    required NoteRole role,
    required DateTime now,
    required bool active,
  }) {
    if (now.isBefore(updatedAt)) {
      throw ArgumentError('Sharing time must not move backwards.');
    }
    return NoteShareGrant(
      note: note,
      recipientId: recipientId,
      role: role,
      sharedAt: sharedAt,
      updatedAt: now,
      accessRevision: accessRevision + 1,
      status: active ? NoteShareStatus.active : NoteShareStatus.revoked,
      revokedAt: active ? null : now,
      sharerLabel: sharerLabel,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NoteShareGrant &&
      note == other.note &&
      recipientId == other.recipientId &&
      role == other.role &&
      sharedAt == other.sharedAt &&
      updatedAt == other.updatedAt &&
      accessRevision == other.accessRevision &&
      status == other.status &&
      revokedAt == other.revokedAt &&
      sharerLabel == other.sharerLabel;
  @override
  int get hashCode => Object.hash(
    note,
    recipientId,
    role,
    sharedAt,
    updatedAt,
    accessRevision,
    status,
    revokedAt,
    sharerLabel,
  );
  @override
  String toString() =>
      'NoteShareGrant(note: $note, role: ${role.name}, '
      'accessRevision: $accessRevision, status: ${status.name})';
}
