import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/sync_cursor.dart';

void main() {
  test('keeps the server value verbatim and never rebuilds it', () {
    const String issued = '  eyJzZXEiOjQyfQ==:page=2  ';
    const SyncCursor cursor = SyncCursor(issued);

    expect(cursor.value, issued);
    expect(cursor.hasValue, isTrue);
    expect(identical(cursor.value, issued), isTrue);
  });

  test('treats an empty value as stored, not as a rewritten cursor', () {
    expect(const SyncCursor('').value, '');
    expect(const SyncCursor('').hasValue, isTrue);
    expect(const SyncCursor(null).hasValue, isFalse);
    expect(const SyncCursor(null).value, isNull);
    expect(const SyncCursor(null), isNot(const SyncCursor('')));
  });

  test('never renders the opaque value', () {
    const SyncCursor cursor = SyncCursor('secret-position-9');

    expect(cursor.toString(), isNot(contains('secret-position-9')));
    expect(const SyncCursor(null).toString(), isNot(contains('null')));
  });

  test('compares by opaque value', () {
    expect(const SyncCursor('a:b'), const SyncCursor('a:b'));
    expect(const SyncCursor('a:b').hashCode, const SyncCursor('a:b').hashCode);
    expect(const SyncCursor('a:b'), isNot(const SyncCursor('b:a')));
    expect(const SyncCursor(null), const SyncCursor(null));
  });
}
