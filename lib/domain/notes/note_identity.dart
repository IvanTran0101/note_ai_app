/// Canonical identity; account cache identity is a separate concern.
final class NoteIdentity {
  NoteIdentity(this.ownerId, this.noteId) {
    if (ownerId.trim().isEmpty || noteId.trim().isEmpty) {
      throw ArgumentError('A canonical note needs an owner and note id.');
    }
  }
  final String ownerId;
  final String noteId;

  /// Length prefixes avoid delimiter and same-note-id collisions.
  String get key =>
      'nf-note:${ownerId.length}:$ownerId${noteId.length}:$noteId';

  /// Existing owned references remain compatible; received references are pairs.
  String referenceFor(String actorId) =>
      ownerId == actorId && !noteId.startsWith('nf-note:') ? noteId : key;

  static NoteIdentity resolve(String reference, String actorId) {
    if (!reference.startsWith('nf-note:')) {
      return NoteIdentity(actorId, reference);
    }
    var rest = reference.substring(8);
    String part() {
      final separator = rest.indexOf(':');
      if (separator <= 0) throw const FormatException('Invalid note reference');
      final length = int.tryParse(rest.substring(0, separator));
      rest = rest.substring(separator + 1);
      if (length == null || length <= 0 || length > rest.length) {
        throw const FormatException('Invalid note reference');
      }
      final value = rest.substring(0, length);
      rest = rest.substring(length);
      return value;
    }

    final owner = part();
    final id = part();
    if (rest.isNotEmpty) throw const FormatException('Invalid note reference');
    final identity = NoteIdentity(owner, id);
    if (identity.key != reference) {
      throw const FormatException('Invalid note reference');
    }
    return identity;
  }

  @override
  bool operator ==(Object other) =>
      other is NoteIdentity &&
      ownerId == other.ownerId &&
      noteId == other.noteId;
  @override
  int get hashCode => Object.hash(ownerId, noteId);
  @override
  String toString() => 'NoteIdentity(ownerId: $ownerId, noteId: $noteId)';
}
