import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_body.dart';
import 'package:note_ai_app/domain/notes/note.dart';

void main() {
  final cases = jsonDecode(
    File('test/fixtures/note_body_cases.json').readAsStringSync(),
  ) as List;
  for (final item in cases) {
    test('body codec ${item['name']}', () {
      expect(NoteBody.plainText(item['content'] as String), item['text']);
      expect(NoteBody.delta(item['content'] as String) != null, item['rich']);
    });
  }
  test('unformatted and empty documents retain plain content', () {
    expect(
      NoteBody.encode([
        {'insert': 'plain\n\n'},
      ]),
      'plain\n',
    );
    expect(
      NoteBody.encode([
        {
          'insert': '\n',
          'attributes': {'header': 1},
        },
      ]),
      '',
    );
  });
  test('formatted text survives storage and remains required', () {
    final encoded = NoteBody.encode([
      {
        'insert': 'body',
        'attributes': {'bold': true, 'size': '24'},
      },
      {'insert': '\n'},
    ]);
    expect(NoteBody.delta(encoded)?.first['attributes'], {
      'bold': true,
      'size': '24',
    });
    expect(NoteBody.plainText(encoded), 'body');
    expect(
      () => Note.create(
        id: 'n',
        ownerId: 'u',
        title: 'Title',
        content:
            '${NoteBody.prefix}[{"insert":"\\n","attributes":{"header":1}}]',
        now: DateTime(2026),
      ),
      throwsArgumentError,
    );
  });
}
