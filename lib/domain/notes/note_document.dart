import 'dart:convert';

import 'document/document_block.dart';
import 'document/document_table.dart';

export 'document/document_block.dart';
export 'document/document_inline.dart';
export 'document/document_marks.dart';
export 'document/document_table.dart';

/// Canonical business content, independent of UI/editor/storage serialization.
final class NoteDocument {
  factory NoteDocument(
    Iterable<DocumentBlock> blocks, {
    bool inlineAttachments = false,
  }) {
    final result = NoteDocument._(List.unmodifiable(blocks), inlineAttachments);
    result._validate();
    return result;
  }
  const NoteDocument._(this.blocks, this.inlineAttachments);
  static const version = 1;
  final List<DocumentBlock> blocks;

  /// True when file references are represented as positioned document blocks.
  /// False is omitted from the provider-neutral wire format for compatibility.
  final bool inlineAttachments;
  String get plainText => blocks.map((block) => block.plainText).join('\n');

  /// IDs referenced by positioned File blocks, including nested containers.
  Set<String> get attachmentReferenceIds {
    final result = <String>{};
    void visit(DocumentBlock block) {
      if (block.kind == DocumentBlockKind.attachment) {
        final id = block.attachmentId;
        if (id != null) result.add(id);
      }
      for (final child in block.children) {
        visit(child);
      }
    }

    for (final block in blocks) {
      visit(block);
    }
    return Set.unmodifiable(result);
  }

  bool referencesAttachment(String attachmentId) =>
      _containsAttachmentReference(blocks, attachmentId);

  /// Removes every positioned File block for an attachment while retaining
  /// all unrelated blocks and their order. This is used only after the owning
  /// attachment removal has been confirmed by the canonical Note writer.
  NoteDocument removeAttachmentReferences(Iterable<String> attachmentIds) {
    final ids = attachmentIds.toSet();
    if (ids.isEmpty) return this;

    var changed = false;
    DocumentBlock? removeFrom(DocumentBlock block) {
      if (block.kind == DocumentBlockKind.attachment &&
          block.attachmentId != null &&
          ids.contains(block.attachmentId)) {
        changed = true;
        return null;
      }

      var childrenChanged = false;
      final children = <DocumentBlock>[];
      for (final child in block.children) {
        final next = removeFrom(child);
        if (next == null) {
          childrenChanged = true;
        } else {
          children.add(next);
          if (!identical(next, child)) childrenChanged = true;
        }
      }
      if (!childrenChanged) return block;
      changed = true;
      return DocumentBlock(
        id: block.id,
        kind: block.kind,
        runs: block.runs,
        children: children,
        level: block.level,
        checked: block.checked,
        icon: block.icon,
        tone: block.tone,
        rows: block.rows,
        headerRow: block.headerRow,
        headerColumn: block.headerColumn,
        attachmentId: block.attachmentId,
      );
    }

    final next = <DocumentBlock>[];
    for (final block in blocks) {
      final result = removeFrom(block);
      if (result != null) next.add(result);
    }
    if (!changed) return this;
    return NoteDocument(next, inlineAttachments: inlineAttachments);
  }

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
    if (!inlineAttachments && blocks.any(_containsAttachmentBlock)) {
      throw ArgumentError(
        'Inline attachment blocks require inline attachment mode.',
      );
    }
    if (utf8.encode(plainText).length > 100000) {
      throw ArgumentError('Document projection exceeds its byte budget.');
    }
  }

  static bool _containsAttachmentBlock(DocumentBlock block) =>
      block.kind == DocumentBlockKind.attachment ||
      block.children.any(_containsAttachmentBlock);

  static bool _containsAttachmentReference(
    Iterable<DocumentBlock> blocks,
    String attachmentId,
  ) => blocks.any(
    (block) =>
        block.kind == DocumentBlockKind.attachment &&
            block.attachmentId == attachmentId ||
        _containsAttachmentReference(block.children, attachmentId),
  );

  @override
  bool operator ==(Object other) =>
      other is NoteDocument &&
      other.inlineAttachments == inlineAttachments &&
      sameDocumentValues(other.blocks, blocks);
  @override
  int get hashCode => Object.hash(inlineAttachments, Object.hashAll(blocks));
  @override
  String toString() =>
      'NoteDocument(version:1, blocks:${blocks.length}, '
      'inlineAttachments:$inlineAttachments, content:<redacted>)';
}
