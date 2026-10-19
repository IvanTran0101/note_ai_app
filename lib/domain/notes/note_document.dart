import 'dart:convert';

import 'document/document_block.dart';
import 'document/document_table.dart';

export 'document/document_block.dart';
export 'document/document_inline.dart';
export 'document/document_marks.dart';
export 'document/document_table.dart';

/// Canonical business content, independent of UI/editor/storage serialization.
final class NoteDocument {
  factory NoteDocument(Iterable<DocumentBlock> blocks) {
    final result = NoteDocument._(List.unmodifiable(blocks));
    result._validate();
    return result;
  }
  const NoteDocument._(this.blocks);
  static const version = 1;
  final List<DocumentBlock> blocks;
  String get plainText => blocks.map((block) => block.plainText).join('\n');

  void _validate() {
    final ids = <String>{};
    var blockCount = 0, cellCount = 0, runCount = 0;
    void identify(String id) {
      if (!ids.add(id)) throw ArgumentError('Duplicate document identity.');
    }

    void visit(DocumentBlock block, int depth) {
      if (++blockCount > 512 || depth > 8) {
        throw ArgumentError('Document structure exceeds its budget.');
      }
      identify(block.id);
      runCount += block.runs.length;
      for (final row in block.rows) {
        identify(row.id);
        for (final cell in row.cells) {
          identify(cell.id);
          cellCount++;
          runCount += cell.runs.length;
        }
      }
      if (cellCount > 512 || runCount > 4096) {
        throw ArgumentError('Document content exceeds its budget.');
      }
      for (final child in block.children) {
        visit(child, depth + 1);
      }
    }

    for (final block in blocks) {
      visit(block, 1);
    }
    if (utf8.encode(plainText).length > 100000) {
      throw ArgumentError('Document projection exceeds its byte budget.');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is NoteDocument && sameDocumentValues(other.blocks, blocks);
  @override
  int get hashCode => Object.hashAll(blocks);
  @override
  String toString() =>
      'NoteDocument(version:1, blocks:${blocks.length}, content:<redacted>)';
}
