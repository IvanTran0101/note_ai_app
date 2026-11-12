import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/infrastructure/documents/note_document_codec.dart';
import 'package:note_ai_app/infrastructure/sync/local_note_state_codec.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_codec_exception.dart';

import '../../domain/notes/m09_document_fixtures.dart' as fixture;

void main() {
  test('all13 choices and semantic marks have canonical JSON roundtrip', () {
    final doc = NoteDocument([
      for (final kind in DocumentBlockKind.values)
        if (kind != DocumentBlockKind.attachment)
          if (kind == DocumentBlockKind.table)
            fixture.table('table')
          else if (kind == DocumentBlockKind.heading)
            for (var level = 1; level <= 4; level++)
              DocumentBlock(
                id: 'h$level',
                kind: kind,
                level: level,
                runs: [DocumentText('Heading $level')],
              )
          else
            DocumentBlock(
              id: kind.name,
              kind: kind,
              checked: kind == DocumentBlockKind.todo ? false : null,
              icon: kind == DocumentBlockKind.callout ? '💡' : null,
              tone: kind == DocumentBlockKind.callout
                  ? DocumentColor.yellow
                  : null,
              runs: kind == DocumentBlockKind.divider
                  ? const []
                  : [
                      DocumentText(
                        'Việt 📝',
                        marks: DocumentMarks(
                          bold: true,
                          italic: true,
                          underline: true,
                          strikethrough: true,
                          color: DocumentColor.purple,
                          highlight: DocumentColor.yellow,
                          fontSize: 32,
                          link: 'https://example.invalid/path',
                        ),
                      ),
                      DocumentMath(r'\sqrt{x^2+1}'),
                    ],
              children: kind == DocumentBlockKind.toggle
                  ? [fixture.block('nested', text: 'Child')]
                  : const [],
            ),
    ]);
    final json = NoteDocumentCodec.encode(doc);
    expect(doc.blocks.length, 13);
    final decoded = NoteDocumentCodec.decode(jsonDecode(jsonEncode(json)));
    expect(decoded, doc);
    expect(NoteDocumentCodec.encode(decoded), json);
    expect(decoded.plainText, doc.plainText);
    expect(jsonEncode(json), isNot(contains('m09_collapsed')));
  });

  test(
    'unknown fields/types, malformed tables and mixed run shapes refuse',
    () {
      final variants = <Map<String, Object?>>[
        {'version': 2, 'blocks': []},
        {'version': 1, 'blocks': [], 'rawEditor': {}},
        {
          'version': 1,
          'blocks': [
            {'id': 'x', 'type': 'page', 'runs': []},
          ],
        },
        {
          'version': 1,
          'blocks': [
            {'id': 'x', 'type': 'paragraph', 'runs': [], 'level': 1},
          ],
        },
        {
          'version': 1,
          'blocks': [
            {'id': 'x', 'type': 'divider', 'runs': []},
          ],
        },
        {
          'version': 1,
          'blocks': [
            {'id': 'x', 'type': 'table', 'rows': []},
          ],
        },
        {
          'version': 1,
          'blocks': [
            {
              'id': 'x',
              'type': 'paragraph',
              'runs': [
                {'type': 'text', 'text': 'private', 'expression': 'private'},
              ],
            },
          ],
        },
      ];
      for (final value in variants) {
        expect(
          () => NoteDocumentCodec.decode(value),
          throwsA(isA<LocalSyncCodecException>()),
        );
      }
    },
  );

  test(
    'invalid marks, links and equation commands refuse without exposing data',
    () {
      final invalid = <Map<String, Object?>>[
        {'fontSize': 11},
        {'fontSize': 49},
        {'fontSize': double.nan},
        {'fontSize': null},
        {'color': '#ff0000'},
        {'bold': 'yes'},
        {'fontFamily': 'external'},
        {'link': 'javascript:privateSecret'},
      ];
      for (final marks in invalid) {
        final raw = runJson({
          'type': 'text',
          'text': 'privateSecret',
          'marks': marks,
        });
        try {
          NoteDocumentCodec.decode(raw);
          fail('Expected refusal');
        } on LocalSyncCodecException catch (error) {
          expect(error.toString(), isNot(contains('privateSecret')));
        }
      }
      expect(
        () => NoteDocumentCodec.decode(
          runJson({'type': 'math', 'expression': r'\input{privateSecret}'}),
        ),
        throwsA(isA<LocalSyncCodecException>()),
      );
    },
  );

  test('cycles/deep hostile input is bounded before decoding', () {
    final cyclic = <Object?>[];
    cyclic.add(cyclic);
    expect(
      () => NoteDocumentCodec.decode({'version': 1, 'blocks': cyclic}),
      throwsA(isA<LocalSyncCodecException>()),
    );
    Object? deep = [];
    for (var i = 0; i < 40; i++) {
      deep = [deep];
    }
    expect(
      () => NoteDocumentCodec.decode(deep),
      throwsA(isA<LocalSyncCodecException>()),
    );
    final duplicate = NoteDocumentCodec.encode(
      NoteDocument([fixture.block('same')]),
    );
    final blocks = duplicate['blocks'] as List;
    blocks.add(blocks.first);
    expect(
      () => NoteDocumentCodec.decode(duplicate),
      throwsA(isA<LocalSyncCodecException>()),
    );
  });

  test('document byte limit covers escaped text and marks independently of projection', () {
    final doc = NoteDocument([
      DocumentBlock(
        id: 'p',
        kind: DocumentBlockKind.paragraph,
        runs: [
          for (var i = 0; i < 110; i++)
            DocumentText(
              'x',
              marks: DocumentMarks(
                link: 'https://example.invalid/${'a' * 1900}$i',
              ),
            ),
        ],
      ),
    ]);
    expect(doc.plainText.length, 110);
    expect(
      () => NoteDocumentCodec.encode(doc),
      throwsA(isA<LocalSyncCodecException>()),
    );
    final escaping = NoteDocument([fixture.block('p', text: '\u0001' * 40000)]);
    expect(
      () => NoteDocumentCodec.encode(escaping),
      throwsA(isA<LocalSyncCodecException>()),
    );
  });

  test(
    'full note bytes are checked without truncating metadata or legacy text',
    () {
      final doc = NoteDocument([fixture.block('p', text: 'x' * 80000)]);
      LocalNoteState note(NoteDocument? value) => LocalNoteState(
        id: 'n',
        ownerId: 'actor',
        title: 't' * 200000,
        content: doc.plainText,
        document: value,
        createdAt: fixture.at,
        updatedAt: fixture.at,
      );
      expect(
        () => LocalNoteStateCodec.encode(note(doc)),
        throwsA(isA<LocalSyncCodecException>()),
      );
      expect(
        LocalNoteStateCodec.decode(LocalNoteStateCodec.encode(note(null))),
        note(null),
      );
    },
  );
}

Map<String, Object?> runJson(Map<String, Object?> run) => {
  'version': 1,
  'blocks': [
    {
      'id': 'p',
      'type': 'paragraph',
      'runs': [run],
    },
  ],
};
