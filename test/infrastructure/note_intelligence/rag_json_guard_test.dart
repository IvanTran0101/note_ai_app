import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/infrastructure/note_intelligence/rag_json_guard.dart';

/// The scanner mirrors the backend's exported `assertNoDuplicateKeys`: a
/// duplicate key, after escape decoding and at any nesting depth, and a payload
/// nested past the contract depth are refused before `jsonDecode` can keep the
/// last value or exhaust the stack.
void main() {
  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

  String reasonOf(void Function() action) {
    try {
      action();
    } on RagJsonProblem catch (problem) {
      return problem.reason;
    }
    return 'accepted';
  }

  group('duplicate keys', () {
    test('accepts a clean object, array, and scalar root', () {
      expect(
        decodeRagJson(bytes('{"a":1,"b":[1,2,{"c":true}]}')),
        isA<Map<String, dynamic>>(),
      );
      expect(decodeRagJson(bytes('[1,2,3]')), isA<List<Object?>>());
      expect(decodeRagJson(bytes('1')), 1);
    });

    test('refuses a raw duplicate key', () {
      expect(
        reasonOf(() => decodeRagJson(bytes('{"accepted":true,"accepted":false}'))),
        'duplicate-key',
      );
    });

    test('refuses an escaped duplicate key', () {
      expect(
        reasonOf(
          () => decodeRagJson(
            bytes(r'{"accepted":true,"\u0061ccepted":false}'),
          ),
        ),
        'duplicate-key',
      );
    });

    test('refuses a duplicate key nested inside an array element', () {
      expect(
        reasonOf(
          () => decodeRagJson(bytes('{"a":[{"b":1,"b":2}]}')),
        ),
        'duplicate-key',
      );
    });

    test('refuses a duplicate key inside a nested object', () {
      expect(
        reasonOf(() => decodeRagJson(bytes('{"outer":{"x":1,"x":2}}'))),
        'duplicate-key',
      );
    });

    test('accepts the same key in different objects', () {
      expect(
        decodeRagJson(bytes('{"a":{"x":1},"b":{"x":2}}')),
        isA<Map<String, dynamic>>(),
      );
    });

    test('accepts an escaped key that is not a duplicate', () {
      final Object? decoded = decodeRagJson(bytes(r'{"\u0061ccepted":true}'));
      expect(decoded, <String, Object?>{'accepted': true});
    });

    test('is not fooled by braces, colons, or escaped quotes in a string', () {
      expect(
        decodeRagJson(bytes(r'{"a":"}{,:[]\"x","b":1}')),
        <String, Object?>{'a': '}{,:[]"x', 'b': 1},
      );
    });

    test('leaves malformed JSON to jsonDecode', () {
      expect(reasonOf(() => decodeRagJson(bytes('{"a":'))), 'malformed');
      expect(reasonOf(() => decodeRagJson(bytes('{'))), 'malformed');
      expect(reasonOf(() => decodeRagJson(bytes(''))), 'malformed');
    });
  });

  group('depth', () {
    String nested(int depth) => '${'[' * depth}1${']' * depth}';

    test('accepts nesting at the contract bound', () {
      expect(decodeRagJson(bytes(nested(ragMaxJsonDepth))), isNotNull);
    });

    test('refuses nesting past the contract bound', () {
      expect(
        reasonOf(() => decodeRagJson(bytes(nested(ragMaxJsonDepth + 1)))),
        'too-deep',
      );
    });

    test('refuses an object nested past the bound', () {
      final String deep = '{"a":' * (ragMaxJsonDepth + 1);
      expect(reasonOf(() => decodeRagJson(bytes(deep))), 'too-deep');
    });
  });

  group('encoding', () {
    test('refuses malformed UTF-8 instead of replacing it', () {
      expect(
        reasonOf(() => decodeRagJson(Uint8List.fromList(<int>[0x7b, 0xff, 0x7d]))),
        'not-utf8',
      );
    });

    test('refuses a body that is not an object or scalar JSON value', () {
      expect(reasonOf(() => decodeRagJson(bytes('nope'))), 'malformed');
    });

    test('reports no payload through its string form', () {
      expect(
        const RagJsonProblem('duplicate-key').toString(),
        'RagJsonProblem(duplicate-key)',
      );
    });
  });
}
