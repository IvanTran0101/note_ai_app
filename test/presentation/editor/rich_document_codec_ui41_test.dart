import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/infrastructure/documents/note_document_codec.dart';
import 'package:note_ai_app/presentation/editor/rich_document_codec.dart';

void main() {
  test(
    'legacy document wire bytes stay unchanged when inline files are off',
    () {
      final document = NoteDocument([
        DocumentBlock(
          id: 'p',
          kind: DocumentBlockKind.paragraph,
          runs: const [DocumentText('Keep')],
        ),
      ]);

      expect(
        jsonEncode(NoteDocumentCodec.encode(document)),
        '{"version":1,"blocks":[{"id":"p","type":"paragraph",'
        '"runs":[{"type":"text","text":"Keep"}]}]}',
      );
    },
  );

  test(
    'File placeholders and references round-trip through storage and editor',
    () {
      final document = NoteDocument([
        DocumentBlock(
          id: 'before',
          kind: DocumentBlockKind.paragraph,
          runs: const [DocumentText('Before')],
        ),
        DocumentBlock(id: 'empty-file', kind: DocumentBlockKind.attachment),
        DocumentBlock(
          id: 'attached-file',
          kind: DocumentBlockKind.attachment,
          attachmentId: 'draft_cache-7',
        ),
        DocumentBlock(
          id: 'after',
          kind: DocumentBlockKind.paragraph,
          runs: const [DocumentText('After')],
        ),
      ], inlineAttachments: true);

      final wire = NoteDocumentCodec.encode(document);
      expect(wire['inlineAttachments'], isTrue);
      expect(NoteDocumentCodec.decode(wire), document);
      expect(document.plainText, 'Before\n\n\nAfter');

      final editor = RichDocumentCodec.encode(document);
      expect(editor.root.attributes['m09_inline_attachments'], isTrue);
      expect(editor.root.children[1].type, 'm09_file');
      expect(editor.root.children[1].attributes['m09_attachment_id'], isNull);
      expect(
        editor.root.children[2].attributes['m09_attachment_id'],
        'draft_cache-7',
      );
      expect(RichDocumentCodec.decode(editor), document);
      expect(
        RichDocumentCodec.decode(engine.Document.fromJson(editor.toJson())),
        document,
      );
    },
  );

  test('File block shape and inline mode are constrained', () {
    expect(
      () => DocumentBlock(
        id: 'file',
        kind: DocumentBlockKind.attachment,
        runs: const [DocumentText('filename.txt')],
      ),
      throwsArgumentError,
    );
    expect(
      () => DocumentBlock(
        id: 'file',
        kind: DocumentBlockKind.attachment,
        attachmentId: 'unsafe/id',
      ),
      throwsArgumentError,
    );
    expect(
      () => NoteDocument([
        DocumentBlock(id: 'file', kind: DocumentBlockKind.attachment),
      ]),
      throwsArgumentError,
    );

    for (final malformed in [
      {
        'version': 1,
        'blocks': [
          {'id': 'file', 'type': 'attachment', 'runs': []},
        ],
        'inlineAttachments': true,
      },
      {
        'version': 1,
        'blocks': [
          {'id': 'file', 'type': 'attachment', 'attachmentId': 'unsafe/id'},
        ],
        'inlineAttachments': true,
      },
      {
        'version': 1,
        'blocks': [
          {'id': 'file', 'type': 'attachment'},
        ],
      },
    ]) {
      expect(
        () => NoteDocumentCodec.decode(malformed),
        throwsA(isA<Exception>()),
      );
    }
  });
}
