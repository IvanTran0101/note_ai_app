/// An owner catalog entry. Identity survives renames and deletion.
final class Label {
  Label._(
    this.id,
    this.ownerId,
    this._name,
    this.createdAt,
    this._updatedAt,
    this._deletedAt,
  );

  factory Label.create({
    required String id,
    required String ownerId,
    required String name,
    required DateTime now,
  }) => Label._(
    requireLabelId(id),
    requireLabelId(ownerId),
    requireLabelName(name),
    now.toUtc(),
    now.toUtc(),
    null,
  );

  factory Label.reconstitute({
    required String id,
    required String ownerId,
    required String name,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) => Label._(
    requireLabelId(id),
    requireLabelId(ownerId),
    requireLabelName(name),
    createdAt.toUtc(),
    updatedAt.toUtc(),
    deletedAt?.toUtc(),
  );

  final String id;
  final String ownerId;
  final DateTime createdAt;
  String _name;
  DateTime _updatedAt;
  DateTime? _deletedAt;
  String get name => _name;
  DateTime get updatedAt => _updatedAt;
  DateTime? get deletedAt => _deletedAt;
  bool get isDeleted => _deletedAt != null;

  void rename(String name, DateTime now) {
    if (isDeleted) throw StateError('A deleted label cannot be renamed.');
    final next = requireLabelName(name);
    if (next == _name) return;
    _name = next;
    _updatedAt = now.toUtc();
  }

  void delete(DateTime now) {
    if (isDeleted) return;
    _deletedAt = _updatedAt = now.toUtc();
  }

  @override
  String toString() => 'Label(id: $id, deleted: $isDeleted, name: <redacted>)';
}

String requireLabelName(String name) {
  final value = name.trim();
  if (value.isEmpty ||
      value.runes.length > 64 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw ArgumentError('Label name must contain 1–64 Unicode characters.');
  }
  return value;
}

String requireLabelId(String id) {
  if (id.trim().isEmpty ||
      id.length > 128 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(id)) {
    throw ArgumentError('Invalid label identity.');
  }
  return id;
}

List<String> freezeLabelIds(Iterable<String> values) {
  final ids = values.map(requireLabelId).toSet().toList()..sort();
  if (ids.length > 32) {
    throw ArgumentError('A note can have at most 32 labels.');
  }
  return List.unmodifiable(ids);
}

bool sameLabelIds(Iterable<String> left, Iterable<String> right) {
  final a = left.toSet(), b = right.toSet();
  return a.length == b.length && a.containsAll(b);
}

/// Validate only additions: tombstone references may survive ordinary edits.
void requireLabelAssociations({
  required String ownerId,
  required Iterable<String> before,
  required Iterable<String> after,
  required Iterable<Label> catalog,
}) {
  final old = before.toSet();
  for (final id in freezeLabelIds(after)) {
    if (old.contains(id)) continue;
    if (!catalog.any(
      (l) => l.id == id && l.ownerId == ownerId && !l.isDeleted,
    )) {
      throw StateError('A new label must be active in the owner catalog.');
    }
  }
}
