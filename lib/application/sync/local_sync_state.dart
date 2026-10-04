/// The complete local sync state of one account.
library;

import 'local_note_state.dart';
import 'pending_mutation.dart';
import 'sync_conflict.dart';
import 'sync_cursor.dart';
import 'sync_mutation.dart';
import '../../domain/notes/note_role.dart';
import '../../domain/users/user_preferences.dart';
import '../labels/local_label_state.dart';

/// Immutable snapshot of everything the local store holds for one account.
///
/// The state is account-scoped and self-consistent: [accountUserId] must not be
/// blank, every projection must authorize that actor, and canonical keys/mutation ids
/// must each be unique. The three collections are copied and exposed
/// read-only, so a caller cannot mutate a state that a store already accepted.
///
/// [cursor] is the opaque remote position last applied for this account. It is
/// null when no cursor has been recorded yet, and it is never interpreted here.
final class LocalSyncState {
  /// Creates a validated, immutable account sync state.
  LocalSyncState({
    required String accountUserId,
    Iterable<LocalNoteState> notes = const <LocalNoteState>[],
    Iterable<PendingMutation> outbox = const <PendingMutation>[],
    Iterable<SyncConflict> conflicts = const <SyncConflict>[],
    this.cursor,
    UserPreferences? userPreferences,
    Iterable<LocalLabelState> labels = const [],
    this.syncWireVersion = 2,
  }) : accountUserId = _requireNonBlank(accountUserId, 'accountUserId'),
       _userPreferences =
           (userPreferences ??
                   UserPreferences.create(
                     userId: accountUserId,
                     theme: AppThemePreference.system,
                     noteFontSize: NoteFontSizePreference.medium,
                   ))
               .copy(),
       notes = List<LocalNoteState>.unmodifiable(notes),
       outbox = List<PendingMutation>.unmodifiable(outbox),
       conflicts = List<SyncConflict>.unmodifiable(conflicts),
       labels = List<LocalLabelState>.unmodifiable(labels) {
    if (syncWireVersion != 1 && syncWireVersion != 2 ||
        this.labels.any((l) => l.ownerId != accountUserId)) {
      throw ArgumentError('Catalog and wire version must belong to the actor.');
    }
    _requireUniqueIds(this.labels.map((l) => l.id), 'labels', 'label id');
    if (_userPreferences.userId != this.accountUserId) {
      throw ArgumentError.value(
        _userPreferences.userId,
        'userPreferences',
        'must belong to the state account',
      );
    }
    _requireUniqueIds(
      this.notes.map((LocalNoteState note) => note.identity.key),
      'notes',
      'note id',
    );
    _requireUniqueIds(
      this.outbox.map((PendingMutation entry) => entry.mutationId),
      'outbox',
      'mutationId',
    );
    for (final LocalNoteState note in this.notes) {
      _requireAccountProjection(note, this.accountUserId);
    }
    for (final entry in this.outbox) {
      _requireActorMutation(entry);
    }
    for (final conflict in this.conflicts) {
      _requireAccountProjection(conflict.local, this.accountUserId);
    }
  }

  void _requireActorMutation(PendingMutation entry) {
    if (entry.isLabel) return;
    final identity = entry.mutation.identityFor(accountUserId);
    if (identity.ownerId == accountUserId) return;
    final note = notes.where((n) => n.identity == identity).firstOrNull;
    final share = note?.share;
    if (share == null ||
        entry.accessRevision == null ||
        entry.operation != SyncMutationOperation.update ||
        !entry.blocked &&
            (!share.isActive ||
                share.role != NoteRole.editor ||
                share.accessRevision != entry.accessRevision)) {
      throw ArgumentError(
        'Foreign mutation requires its canonical editor epoch.',
      );
    }
  }

  /// The account this state belongs to.
  final String accountUserId;
  final List<LocalLabelState> labels;
  final int syncWireVersion;

  final UserPreferences _userPreferences;

  /// Detached account preference values, so callers cannot mutate a stored
  /// snapshot without going through its transaction.
  UserPreferences get userPreferences => _userPreferences.copy();

  /// Every stored note of the account, including local tombstones.
  final List<LocalNoteState> notes;

  /// Queued mutations waiting to be pushed, in queue order.
  final List<PendingMutation> outbox;

  /// Unresolved conflicts recorded for the account.
  final List<SyncConflict> conflicts;

  /// The opaque remote position last applied, or null when none is recorded.
  final SyncCursor? cursor;

  /// True when the account has no notes, no outbox entries, and no conflicts.
  bool get isEmpty =>
      notes.isEmpty && outbox.isEmpty && conflicts.isEmpty && labels.isEmpty;

  @override
  bool operator ==(Object other) {
    return other is LocalSyncState &&
        other.accountUserId == accountUserId &&
        other._userPreferences == _userPreferences &&
        _listEquals(other.labels, labels) &&
        other.syncWireVersion == syncWireVersion &&
        _listEquals(other.notes, notes) &&
        _listEquals(other.outbox, outbox) &&
        _listEquals(other.conflicts, conflicts) &&
        other.cursor == cursor;
  }

  @override
  int get hashCode => Object.hash(
    accountUserId,
    _userPreferences,
    Object.hashAll(notes),
    Object.hashAll(outbox),
    Object.hashAll(conflicts),
    cursor,
    Object.hashAll(labels),
    syncWireVersion,
  );

  @override
  String toString() {
    return 'LocalSyncState(accountUserId: $accountUserId, '
        'notes: ${notes.length}, outbox: ${outbox.length}, '
        'conflicts: ${conflicts.length}, '
        'cursor: ${cursor == null ? 'none' : 'present'})';
  }
}

void _requireUniqueIds(Iterable<String> ids, String listName, String idName) {
  final Set<String> seen = <String>{};
  for (final String id in ids) {
    if (!seen.add(id)) {
      throw ArgumentError.value(id, listName, 'contains a duplicate $idName');
    }
  }
}

String _requireNonBlank(String value, String fieldName) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, fieldName, 'must not be blank');
  }
  return value;
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

void _requireAccountProjection(LocalNoteState note, String actorId) {
  if (note.ownerId == actorId) {
    if (note.share != null) {
      throw ArgumentError('Owned projections must not carry recipient access.');
    }
    return;
  }
  final share = note.share;
  if (share == null ||
      share.recipientId != actorId ||
      share.note != note.identity ||
      (!share.isActive &&
          (note.contentAvailable ||
              note.title.isNotEmpty ||
              note.content.isNotEmpty))) {
    throw ArgumentError.value(
      note.ownerId,
      'notes',
      'Foreign projection needs matching actor access.',
    );
  }
}
