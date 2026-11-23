import 'document_inline.dart';
import 'document_marks.dart';
import 'document_table.dart';

enum DocumentBlockKind {
  paragraph,
  heading,
  bulletedList,
  numberedList,
  todo,
  toggle,
  callout,
  quote,
  table,
  divider,
  attachment,
}

/// Immutable business block. Textual children retain structure when converting
/// a container to Text; table cells contain inline runs, never child notes.
final class DocumentBlock {
  factory DocumentBlock({
    required String id,
    required DocumentBlockKind kind,
    Iterable<DocumentInline> runs = const [],
    Iterable<DocumentBlock> children = const [],
    int? level,
    bool? checked,
    String? icon,
    DocumentColor? tone,
    Iterable<DocumentRow> rows = const [],
    bool headerRow = false,
    bool headerColumn = false,
    String? attachmentId,
  }) {
    requireDocumentId(id);
    final block = DocumentBlock._(
      id,
      kind,
      freezeDocumentRuns(runs),
      List.unmodifiable(children),
      level,
      checked,
      icon,
      tone,
      List.unmodifiable(rows),
      headerRow,
      headerColumn,
      attachmentId,
    );
    block._validate();
    return block;
  }
  const DocumentBlock._(
    this.id,
    this.kind,
    this.runs,
    this.children,
    this.level,
    this.checked,
    this.icon,
    this.tone,
    this.rows,
    this.headerRow,
    this.headerColumn,
    this.attachmentId,
  );
  final String id;
  final DocumentBlockKind kind;
  final List<DocumentInline> runs;
  final List<DocumentBlock> children;
  final int? level;
  final bool? checked;
  final String? icon;
  final DocumentColor? tone;
  final List<DocumentRow> rows;
  final bool headerRow, headerColumn;

  /// Canonical local attachment reference. Null represents an empty File block.
  final String? attachmentId;

  void _validate() {
    if (kind == DocumentBlockKind.heading
        ? level == null || level! < 1 || level! > 4
        : level != null) {
      throw ArgumentError('Invalid document heading level.');
    }
    if (kind == DocumentBlockKind.todo ? checked == null : checked != null) {
      throw ArgumentError('Invalid document checkbox.');
    }
    if (kind != DocumentBlockKind.callout && (icon != null || tone != null)) {
      throw ArgumentError('Callout attributes require a callout.');
    }
    if (icon != null &&
        (icon!.isEmpty ||
            icon!.runes.length > 16 ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(icon!))) {
      throw ArgumentError('Invalid callout icon.');
    }
    if (kind == DocumentBlockKind.table) {
      _validateTable();
    } else if (rows.isNotEmpty || headerRow || headerColumn) {
      throw ArgumentError('Table attributes require a table.');
    }
    if (kind == DocumentBlockKind.attachment) {
      if (runs.isNotEmpty || children.isNotEmpty) {
        throw ArgumentError('File blocks cannot contain text or children.');
      }
      if (attachmentId != null) requireDocumentId(attachmentId!);
    } else if (attachmentId != null) {
      throw ArgumentError('Attachment identity requires a File block.');
    }
    if ((kind == DocumentBlockKind.table ||
            kind == DocumentBlockKind.divider ||
            kind == DocumentBlockKind.attachment) &&
        (runs.isNotEmpty || children.isNotEmpty)) {
      throw ArgumentError(
        'Table/divider cannot contain block text or children.',
      );
    }
  }

  void _validateTable() {
    if (rows.isEmpty ||
        rows.length > 32 ||
        rows.first.cells.isEmpty ||
        rows.first.cells.length > 12 ||
        rows.any((row) => row.cells.length != rows.first.cells.length)) {
      throw ArgumentError('Invalid document table grid.');
    }
  }

  String get plainText {
    if (kind == DocumentBlockKind.table) {
      return rows
          .map((row) => row.cells.map((cell) => cell.plainText).join('\t'))
          .join('\n');
    }
    final text = runs.map((run) => run.plainText).join();
    return [text, ...children.map((child) => child.plainText)].join('\n');
  }

  @override
  bool operator ==(Object other) =>
      other is DocumentBlock &&
      other.id == id &&
      other.kind == kind &&
      other.attachmentId == attachmentId &&
      other.level == level &&
      other.checked == checked &&
      other.icon == icon &&
      other.tone == tone &&
      other.headerRow == headerRow &&
      other.headerColumn == headerColumn &&
      sameDocumentValues(other.runs, runs) &&
      sameDocumentValues(other.children, children) &&
      sameDocumentValues(other.rows, rows);
  @override
  int get hashCode => Object.hash(
    id,
    kind,
    attachmentId,
    level,
    checked,
    icon,
    tone,
    headerRow,
    headerColumn,
    Object.hashAll(runs),
    Object.hashAll(children),
    Object.hashAll(rows),
  );
}
