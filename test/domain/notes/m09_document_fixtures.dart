import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';

final at = DateTime.utc(2026, 10, 14);
DocumentBlock block(
  String id, {
  String text = '',
  List<DocumentBlock> children = const [],
}) => DocumentBlock(
  id: id,
  kind: DocumentBlockKind.paragraph,
  runs: [DocumentText(text)],
  children: children,
);
Note create(NoteDocument document) => Note.create(
  id: 'n',
  ownerId: 'owner',
  title: 'Title',
  content: document.plainText,
  document: document,
  now: at,
);
DocumentBlock table(String id, {int rows = 2, int columns = 2}) =>
    DocumentBlock(
      id: id,
      kind: DocumentBlockKind.table,
      rows: [
        for (var r = 0; r < rows; r++)
          DocumentRow(
            id: '${id}_r$r',
            cells: [
              for (var c = 0; c < columns; c++)
                DocumentCell(
                  id: '${id}_c${r}_$c',
                  runs: [
                    DocumentText(String.fromCharCode(65 + r * columns + c)),
                  ],
                ),
            ],
          ),
      ],
    );
