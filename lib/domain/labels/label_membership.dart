import 'label.dart';

/// A frozen set value also usable as a const empty DTO default.
final class LabelMembership {
  const LabelMembership.empty() : values = const [];
  LabelMembership(Iterable<String> ids) : values = freezeLabelIds(ids);
  final List<String> values;
  @override
  bool operator ==(Object other) =>
      other is LabelMembership && sameLabelIds(values, other.values);
  @override
  int get hashCode => Object.hashAll(values);
}
