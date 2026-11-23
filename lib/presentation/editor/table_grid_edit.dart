import '../../domain/notes/note_document.dart';

enum TableChange {
  addRow,
  removeRow,
  addColumn,
  removeColumn,
  headerRow,
  headerColumn,
  paragraphAfter,
}

/// Pure table shape editing. It preserves IDs/data in every unaffected cell.
final class TableGridEdit {
  TableGridEdit(this.original, this.row, this.column, this.newId)
    : rows = original.rows.toList();
  final DocumentBlock original;
  final String Function() newId;
  final List<DocumentRow> rows;
  int row, column;
  bool apply(TableChange change) {
    switch (change) {
      case TableChange.addRow:
        if (rows.length >= 32) return false;
        rows.insert(
          row + 1,
          DocumentRow(
            id: newId(),
            cells: [
              for (var i = 0; i < rows.first.cells.length; i++)
                DocumentCell(id: newId(), runs: const []),
            ],
          ),
        );
        row++;
      case TableChange.removeRow:
        if (rows.length == 1) return false;
        rows.removeAt(row);
        row = row.clamp(0, rows.length - 1);
      case TableChange.addColumn:
        if (rows.first.cells.length >= 12) return false;
        _columns(add: true);
        column++;
      case TableChange.removeColumn:
        if (rows.first.cells.length == 1) return false;
        _columns(add: false);
        column = column.clamp(0, rows.first.cells.length - 1);
      case TableChange.headerRow:
      case TableChange.headerColumn:
        break;
      case TableChange.paragraphAfter:
        return false;
    }
    return true;
  }

  void _columns({required bool add}) {
    for (var r = 0; r < rows.length; r++) {
      final cells = rows[r].cells.toList();
      if (add) {
        cells.insert(column + 1, DocumentCell(id: newId(), runs: const []));
      } else {
        cells.removeAt(column);
      }
      rows[r] = DocumentRow(id: rows[r].id, cells: cells);
    }
  }

  DocumentBlock result(TableChange change) => DocumentBlock(
    id: original.id,
    kind: DocumentBlockKind.table,
    rows: rows,
    headerRow: change == TableChange.headerRow
        ? !original.headerRow
        : original.headerRow,
    headerColumn: change == TableChange.headerColumn
        ? !original.headerColumn
        : original.headerColumn,
  );
}
