part of 'rich_document_codec.dart';

engine.Node _tableNode(DocumentBlock block) {
  final columns = block.rows.first.cells.length;
  final table = engine.TableNode.fromList<engine.Node>([
    for (var col = 0; col < columns; col++)
      [
        for (final row in block.rows)
          engine.paragraphNode(
            delta: RichInlineCodec.encode(row.cells[col].runs),
          ),
      ],
  ]).node;
  table.updateAttributes({
    ...table.attributes,
    RichDocumentCodec.identity: block.id,
    'm09_header_row': block.headerRow,
    'm09_header_column': block.headerColumn,
  });
  for (final cell in table.children) {
    final row = cell.attributes[engine.TableCellBlockKeys.rowPosition] as int;
    final col = cell.attributes[engine.TableCellBlockKeys.colPosition] as int;
    cell.updateAttributes({
      ...cell.attributes,
      RichDocumentCodec.identity: block.rows[row].cells[col].id,
      RichDocumentCodec.rowIdentity: block.rows[row].id,
    });
  }
  return table;
}

DocumentBlock _tableBlock(engine.Node node) {
  final rows = node.attributes[engine.TableBlockKeys.rowsLen];
  final cols = node.attributes[engine.TableBlockKeys.colsLen];
  if (rows is! int ||
      cols is! int ||
      rows < 1 ||
      rows > 32 ||
      cols < 1 ||
      cols > 12 ||
      node.children.length != rows * cols) {
    throw StateError('Invalid editor table.');
  }
  final cells = <String, engine.Node>{};
  for (final cell in node.children) {
    final key =
        '${cell.attributes[engine.TableCellBlockKeys.rowPosition]}:${cell.attributes[engine.TableCellBlockKeys.colPosition]}';
    if (cells.containsKey(key)) {
      throw StateError('Duplicate editor table cell.');
    }
    cells[key] = cell;
  }
  final result = <DocumentRow>[];
  for (var row = 0; row < rows; row++) {
    final members = <DocumentCell>[];
    String? rowId;
    for (var col = 0; col < cols; col++) {
      final cell = cells['$row:$col'];
      if (cell == null) throw StateError('Editor table cell missing.');
      final current = cell.attributes[RichDocumentCodec.rowIdentity];
      if (current is! String || rowId != null && current != rowId) {
        throw StateError('Editor table row identity mismatch.');
      }
      rowId = current;
      final runs = <DocumentInline>[];
      for (var p = 0; p < cell.children.length; p++) {
        final paragraph = cell.children[p];
        if (paragraph.type != 'paragraph' || paragraph.children.isNotEmpty) {
          throw StateError('Table cells support inline paragraphs only.');
        }
        if (p > 0) runs.add(const DocumentText('\n'));
        runs.addAll(RichInlineCodec.decode(paragraph.delta));
      }
      members.add(DocumentCell(id: RichDocumentCodec.id(cell), runs: runs));
    }
    result.add(DocumentRow(id: rowId!, cells: members));
  }
  return DocumentBlock(
    id: RichDocumentCodec.id(node),
    kind: DocumentBlockKind.table,
    rows: result,
    headerRow: node.attributes['m09_header_row'] == true,
    headerColumn: node.attributes['m09_header_column'] == true,
  );
}
