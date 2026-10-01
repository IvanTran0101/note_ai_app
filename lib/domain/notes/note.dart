/// The Note aggregate root for the notes domain.
///
/// It owns note text, pin state, and their invariants. It does not save itself,
/// run AI, or map itself to UI data.
class Note {
  Note._(
    this._id,
    this._ownerId,
    this._title,
    this._content,
    this._createdAt,
    this._updatedAt,
    this._pinnedAt,
  );

  /// Creates a new note with valid text and identical creation/update times.
  factory Note.create({
    required String id,
    required String ownerId,
    required String title,
    required String content,
    required DateTime now,
  }) {
    _requireText(title, 'title');
    _requireText(content, 'content');
    return Note._(id, ownerId, title, content, now, now, null);
  }

  /// Restores persisted values without applying current write validation.
  factory Note.reconstitute({
    required String id,
    required String ownerId,
    required String title,
    required String content,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? pinnedAt,
  }) => Note._(id, ownerId, title, content, createdAt, updatedAt, pinnedAt);

  final String _id;
  final String _ownerId;
  final DateTime _createdAt;
  String _title;
  String _content;
  DateTime _updatedAt;
  DateTime? _pinnedAt;

  String get id => _id;
  String get ownerId => _ownerId;
  String get title => _title;
  String get content => _content;
  DateTime get createdAt => _createdAt;
  DateTime get updatedAt => _updatedAt;
  DateTime? get pinnedAt => _pinnedAt;

  /// Renames the note while preserving the entered text exactly.
  void rename(String title, DateTime now) {
    _requireText(title, 'title');
    _title = title;
    _updatedAt = now;
  }

  /// Replaces note content while preserving its formatting.
  void replaceContent(String content, DateTime now) {
    _requireText(content, 'content');
    _content = content;
    _updatedAt = now;
  }

  /// Atomically changes both fields used by the editor.
  void replaceText(String title, String content, DateTime now) {
    _requireText(title, 'title');
    _requireText(content, 'content');
    _title = title;
    _content = content;
    _updatedAt = now;
  }

  /// Pins once; repeated requests do not move a note to the top again.
  void pin(DateTime now) {
    if (_pinnedAt != null) return;
    _pinnedAt = now;
    _updatedAt = now;
  }

  /// Unpins the note. Repeated requests are a no-op.
  void unpin(DateTime now) {
    if (_pinnedAt == null) return;
    _pinnedAt = null;
    _updatedAt = now;
  }

  @override
  String toString() =>
      'Note(id: $_id, ownerId: $_ownerId, createdAt: $_createdAt, '
      'updatedAt: $_updatedAt, pinnedAt: $_pinnedAt)';
}

void _requireText(String value, String field) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, field, 'must not be blank');
  }
}
