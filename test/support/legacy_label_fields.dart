/// Removes only M04 fields when constructing a published pre-M04 fixture.
/// Attempted payloads are deliberately untouched.
void stripM04Fields(Map<String, dynamic> document) {
  document.remove('labels');
  document.remove('syncWireVersion');
  void note(dynamic value) {
    if (value is! Map) return;
    value.remove('labelIds');
    value.remove('labelProjections');
    value.remove('includesLabels');
  }

  for (final value in document['notes'] as List) {
    note(value);
  }
  for (final value in document['conflicts'] as List) {
    note(value['local']);
    note(value['remote']);
  }
}
