import 'label.dart';

/// Sanitized names scoped by the containing readable Note; never a catalog.
final class LabelProjection {
  LabelProjection({required String id, required String name})
    : id = requireLabelId(id),
      name = requireLabelName(name);
  final String id;
  final String name;
  @override
  bool operator ==(Object other) =>
      other is LabelProjection && other.id == id && other.name == name;
  @override
  int get hashCode => Object.hash(id, name);
  @override
  String toString() => 'LabelProjection(id: $id, name: <redacted>)';
}
