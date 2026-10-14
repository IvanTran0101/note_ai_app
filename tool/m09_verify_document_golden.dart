import 'dart:convert';
import 'dart:io';

import '../lib/infrastructure/documents/note_document_codec.dart';

/// Direct Dart runner for the same provider-neutral fixture used by backend
/// tests; no Flutter runtime, platform store, native hook or model inference.
void main() {
  final fixture = jsonDecode(
    File.fromUri(Platform.script.resolve('../test/fixtures/m09_document_v1.json'))
        .readAsStringSync(),
  ) as Map<String, dynamic>;
  final document = NoteDocumentCodec.decode(fixture['document']);
  if (!_same(NoteDocumentCodec.encode(document), fixture['document']) ||
      document.plainText != fixture['projection']) {
    throw StateError('Dart/backend document contract golden mismatch.');
  }
  stdout.writeln('Dart/backend document golden PASS.');
}

bool _same(Object? left, Object? right) {
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.keys.every((key) => right.containsKey(key) && _same(left[key], right[key]));
  }
  if (left is List && right is List) {
    return left.length == right.length &&
        Iterable<int>.generate(left.length).every((i) => _same(left[i], right[i]));
  }
  return left == right;
}
