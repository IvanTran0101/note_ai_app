import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/editor_projection_map.dart';
import 'package:note_ai_app/presentation/editor/rich_document_codec.dart';

void main() {
  test('table/toggle/equation projection equals canonical content; equation maps whole atom', () {
    final document = NoteDocument([
      DocumentBlock(
        id: 'p',
        kind: DocumentBlockKind.paragraph,
        runs: [
          const DocumentText('A'),
          DocumentMath(r'\sqrt{x}'),
          const DocumentText('B'),
        ],
        children: [
          DocumentBlock(
            id: 'child',
            kind: DocumentBlockKind.toggle,
            runs: const [DocumentText('nested')],
          ),
        ],
      ),
      DocumentBlock(
        id: 'table',
        kind: DocumentBlockKind.table,
        rows: [
          DocumentRow(
            id: 'row',
            cells: [
              DocumentCell(id: 'c1', runs: const [DocumentText('cell\nmore')]),
              DocumentCell(id: 'c2', runs: const [DocumentText('second')]),
            ],
          ),
        ],
      ),
    ]);
    final map = EditorProjectionMap(RichDocumentCodec.encode(document));
    expect(map.plainText, document.plainText);
    final equation = map.selection(2, 5)!;
    expect(equation.start.offset, 1);
    expect(equation.end.offset, 2);
    final table = map.selection(
      document.plainText.indexOf('second'),
      document.plainText.length,
    )!;
    expect(table.start.path, [1, 1, 0]);
    expect(table.start.offset, 0);
    expect(table.end.offset, 6);
  });
}
