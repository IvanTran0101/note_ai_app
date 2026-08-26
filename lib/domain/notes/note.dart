/// The Note aggregate root for the notes domain.
///
/// Owns its state and invariants. It does not save itself, run AI, or map
/// itself to UI data (see the README architecture section). All fields are
/// exposed read-only; [title], [content], and [updatedAt] change only through
/// [rename] and [replaceContent], and [id], [ownerId], and [createdAt] never
/// change after creation.
class Note {
  /// Internal construction used by [Note.create]. The final two arguments are
  /// [createdAt] and [updatedAt], both seeded from the factory's [now].
  Note._(
    this._id,
    this._ownerId,
    this._title,
    this._content,
    this._createdAt,
    this._updatedAt,
  );

  /// Creates a new note. Both [createdAt] and [updatedAt] are initialized from
  /// the supplied [now].
  factory Note.create({
    required String id,
    required String ownerId,
    required String title,
    required String content,
    required DateTime now,
  }) {
    return Note._(id, ownerId, title, content, now, now);
  }

  final String _id;
  final String _ownerId;
  final DateTime _createdAt;
  String _title;
  String _content;
  DateTime _updatedAt;

  /// The identity of this note.
  String get id => _id;

  /// The identity of the user who owns this note.
  String get ownerId => _ownerId;

  /// The current title.
  String get title => _title;

  /// The current content.
  String get content => _content;

  /// When this note was created. Never changes after creation.
  DateTime get createdAt => _createdAt;

  /// When this note was last modified.
  DateTime get updatedAt => _updatedAt;

  /// Renames the note and records [now] as the last modification time.
  void rename(String title, DateTime now) {
    _title = title;
    _updatedAt = now;
  }

  /// Replaces the note content and records [now] as the last modification
  /// time.
  void replaceContent(String content, DateTime now) {
    _content = content;
    _updatedAt = now;
  }

  @override
  String toString() {
    return 'Note(id: $_id, ownerId: $_ownerId, title: $_title, '
        'createdAt: $_createdAt, updatedAt: $_updatedAt)';
  }
}
