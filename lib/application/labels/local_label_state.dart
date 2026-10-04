import '../../domain/labels/label.dart';
import '../sync/note_sync_status.dart';

/// Immutable catalog row in the actor's existing encrypted sync document.
final class LocalLabelState {
  LocalLabelState({
    required String id,
    required String ownerId,
    required String name,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.serverRevision = 0,
    this.status = NoteSyncStatus.synced,
    this.conflictRemote,
  }) : id = requireLabelId(id),
       ownerId = requireLabelId(ownerId),
       name = requireLabelName(name) {
    if (serverRevision < 0 ||
        conflictRemote?.id != null &&
            (conflictRemote!.id != id || conflictRemote!.ownerId != ownerId)) {
      throw ArgumentError('Invalid label revision or conflict identity.');
    }
  }
  final String id, ownerId, name;
  final DateTime createdAt, updatedAt;
  final DateTime? deletedAt;
  final int serverRevision;
  final NoteSyncStatus status;
  final LocalLabelState? conflictRemote;
  bool get isDeleted => deletedAt != null;
  String get key => 'label:$ownerId:$id';
  Label toDomain() => Label.reconstitute(
    id: id,
    ownerId: ownerId,
    name: name,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );
  LocalLabelState withStatus(
    NoteSyncStatus next, {
    int? revision,
    LocalLabelState? remote,
  }) => LocalLabelState(
    id: id,
    ownerId: ownerId,
    name: name,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
    serverRevision: revision ?? serverRevision,
    status: next,
    conflictRemote: remote,
  );
  @override
  bool operator ==(Object other) =>
      other is LocalLabelState &&
      other.id == id &&
      other.ownerId == ownerId &&
      other.name == name &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt &&
      other.serverRevision == serverRevision &&
      other.status == status &&
      other.conflictRemote == conflictRemote;
  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    name,
    createdAt,
    updatedAt,
    deletedAt,
    serverRevision,
    status,
    conflictRemote,
  );
  @override
  String toString() =>
      'LocalLabelState(id: $id, status: $status, name: <redacted>)';
}
