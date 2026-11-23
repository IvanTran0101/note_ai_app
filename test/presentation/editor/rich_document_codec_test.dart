import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/rich_document_codec.dart';
import 'package:note_ai_app/presentation/editor/rich_inline_codec.dart';

import '../../domain/notes/m09_document_fixtures.dart' as fixture;

void main() {
  test(
    'approved13 block choices/marks/table convert losslessly through engine',
    () {
      final document = _allBlocks();
      final converted = RichDocumentCodec.encode(document);
      expect(RichDocumentCodec.decode(converted), document);
      final reopened = engine.Document.fromJson(converted.toJson());
      expect(RichDocumentCodec.decode(reopened), document);
      expect(converted.root.children.length, 13);
    },
  );
  test('virtual empty document stays empty; legacy text including newlines is exact', () {
    final empty = NoteDocument([]);
    expect(RichDocumentCodec.decode(RichDocumentCodec.encode(empty)), empty);
    final legacy = 'Việt 📝\n\nlast\n';
    expect(
      RichDocumentCodec.decode(RichDocumentCodec.legacy(legacy)).plainText,
      legacy,
    );
  });
  test(
    'adjacent matching math atoms survive Delta normalization independently',
    () {
      final document = NoteDocument([
        DocumentBlock(
          id: 'p',
          kind: DocumentBlockKind.paragraph,
          runs: [
            DocumentMath('x'),
            DocumentMath('x'),
            const DocumentText('after'),
          ],
        ),
      ]);
      expect(
        RichDocumentCodec.decode(RichDocumentCodec.encode(document)),
        document,
      );
      expect(
        () => RichInlineCodec.decode(
          engine.Delta()..insert('ordinary', attributes: {'m09_math': 'x'}),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'table cell multiline paragraphs flatten without losing cell/row identity',
    () {
      final document = NoteDocument([fixture.table('table')]);
      final converted = RichDocumentCodec.encode(document);
      final cell = converted.root.children.single.children.first;
      final original = (cell.children.first.delta!).toPlainText();
      cell.insert(engine.paragraphNode(text: 'second line'));
      final decoded = RichDocumentCodec.decode(converted).blocks.single;
      expect(decoded.rows.first.id, document.blocks.single.rows.first.id);
      expect(
        decoded.rows.first.cells.first.id,
        document.blocks.single.rows.first.cells.first.id,
      );
      expect(
        decoded.rows.first.cells.first.plainText,
        '$original\nsecond line',
      );
    },
  );
}

NoteDocument _allBlocks() => NoteDocument([
  DocumentBlock(
    id: 'text',
    kind: DocumentBlockKind.paragraph,
    runs: [
      DocumentText(
        'Việt 📝',
        marks: DocumentMarks(
          bold: true,
          italic: true,
          underline: true,
          strikethrough: true,
          fontSize: 24,
          color: DocumentColor.red,
          highlight: DocumentColor.yellow,
          link: 'https://example.invalid',
        ),
      ),
      DocumentMath(r'\sqrt{x^2+1}'),
    ],
    children: [fixture.block('nested', text: 'Nested')],
  ),
  for (var level = 1; level <= 4; level++)
    DocumentBlock(
      id: 'h$level',
      kind: DocumentBlockKind.heading,
      level: level,
      runs: [DocumentText('Heading$level')],
    ),
  for (final kind in [
    DocumentBlockKind.bulletedList,
    DocumentBlockKind.numberedList,
    DocumentBlockKind.toggle,
    DocumentBlockKind.quote,
  ])
    DocumentBlock(id: kind.name, kind: kind, runs: [DocumentText(kind.name)]),
  DocumentBlock(
    id: 'todo',
    kind: DocumentBlockKind.todo,
    checked: true,
    runs: const [DocumentText('Task')],
  ),
  DocumentBlock(
    id: 'callout',
    kind: DocumentBlockKind.callout,
    icon: '💡',
    tone: DocumentColor.purple,
    runs: const [DocumentText('Callout')],
  ),
  fixture.table('table'),
  DocumentBlock(id: 'divider', kind: DocumentBlockKind.divider),
]);
