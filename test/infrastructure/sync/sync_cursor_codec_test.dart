import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/sync_cursor.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_codec_exception.dart';
import 'package:note_ai_app/infrastructure/sync/sync_cursor_codec.dart';

import 'local_sync_codec_fixtures.dart';

void main() {
  test('encodes null as no cursor and a cursor as its raw value', () {
    expect(SyncCursorCodec.encode(null), isNull);
    expect(SyncCursorCodec.encode(const SyncCursor('offset:12')), 'offset:12');
  });

  test('decodes null as no cursor', () {
    expect(SyncCursorCodec.decode(null), isNull);
  });

  test('keeps the value byte-for-byte, including whitespace and unicode', () {
    const List<String> values = <String>[
      '',
      ' ',
      '  padded  ',
      'line\nbreak\ttab',
      '✓ emoji 🎉 ünïcode',
      'eyJvZmZzZXQiOiIxMiJ9==',
      '0',
    ];

    for (final String value in values) {
      final SyncCursor? decoded = SyncCursorCodec.decode(value);
      expect(decoded, SyncCursor(value));
      expect(decoded!.value, value);
      expect(decoded.hasValue, isTrue);
      expect(SyncCursorCodec.encode(decoded), value);
    }
  });

  test('rejects a stored value that is not text', () {
    for (final Object? value in <Object?>[
      0,
      1.5,
      true,
      <Object?>[],
      <String, Object?>{'cursor': 'x'},
    ]) {
      final LocalSyncCodecException error = codecFailure(
        () => SyncCursorCodec.decode(value, path: 'localSyncState.cursor'),
      );
      expect(error.message, 'must be a string or null.');
      expect(error.path, 'localSyncState.cursor');
    }
  });

  test('never renders a cursor value in a failure', () {
    final LocalSyncCodecException error = codecFailure(
      () => SyncCursorCodec.decode(42, path: 'localSyncState.cursor'),
    );

    expect(error.toString(), isNot(contains(secretCursor)));
    expect(error.toString(), isNot(contains('42')));
  });
}
