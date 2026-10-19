import 'dart:convert';

import '../../domain/notes/note_document.dart';
import '../sync/local_sync_codec_exception.dart';
import 'document_codec_reader.dart';
import 'document_marks_codec.dart';

/// Provider neutral canonical JSON. Raw editor JSON is never persisted.
abstract final class NoteDocumentCodec {
  static Map<String, Object?> encode(NoteDocument document) {
    final result = <String, Object?>{
      'version': NoteDocument.version,
      'blocks': document.blocks.map(_block).toList(),
    };
    if (utf8.encode(jsonEncode(result)).length > 180000) {
      throw const LocalSyncCodecException(
        'Rich document exceeds its byte budget.',
        path: 'document',
      );
    }
    return result;
  }

  static NoteDocument? decodeOptional(Object? data) =>
      data == null ? null : decode(data);

  static NoteDocument decode(Object? data) {
    final reader = DocumentCodecReader()..inspect(data);
    try {
      final root = reader.object(data, const {'version', 'blocks'});
      if (reader.integer(root['version']) != NoteDocument.version) {
        reader.fail();
      }
      final document = NoteDocument([
        for (final block in reader.list(root['blocks'], 512))
          _decodeBlock(block, reader, 1),
      ]);
      // Escaping can increase JSON bytes beyond the preflight traversal count.
      encode(document);
      return document;
    } on ArgumentError {
      reader.fail();
    }
  }

  static Map<String, Object?> _block(DocumentBlock block) => {
    'id': block.id,
    'type': block.kind.name,
    if (block.kind != DocumentBlockKind.table &&
        block.kind != DocumentBlockKind.divider)
      'runs': block.runs.map(_run).toList(),
    if (block.children.isNotEmpty)
      'children': block.children.map(_block).toList(),
    if (block.level != null) 'level': block.level,
    if (block.checked != null) 'checked': block.checked,
    if (block.icon != null) 'icon': block.icon,
    if (block.tone != null) 'tone': block.tone!.name,
    if (block.kind == DocumentBlockKind.table) ...{
      'rows': [
        for (final row in block.rows)
          {
            'id': row.id,
            'cells': [
              for (final cell in row.cells)
                {'id': cell.id, 'runs': cell.runs.map(_run).toList()},
            ],
          },
      ],
      if (block.headerRow) 'headerRow': true,
      if (block.headerColumn) 'headerColumn': true,
    },
  };

  static Map<String, Object?> _run(DocumentInline run) => {
    if (run is DocumentText) ...{'type': 'text', 'text': run.text},
    if (run is DocumentMath) ...{'type': 'math', 'expression': run.expression},
    if (run.marks != const DocumentMarks.plain())
      'marks': DocumentMarksCodec.encode(run.marks),
  };

  static List<DocumentInline> _runs(Object? raw, DocumentCodecReader reader) {
    final values = reader.list(raw, 4096);
    if ((reader.runs += values.length) > 4096) reader.fail();
    return [for (final value in values) _decodeRun(value, reader)];
  }

  static DocumentInline _decodeRun(Object? raw, DocumentCodecReader reader) {
    final map = reader.object(
      raw,
      const {'type'},
      const {'text', 'expression', 'marks'},
    );
    final marks = map.containsKey('marks')
        ? DocumentMarksCodec.decode(map['marks'], reader)
        : const DocumentMarks.plain();
    switch (map['type']) {
      case 'text':
        if (map.containsKey('expression')) reader.fail();
        return DocumentText(reader.string(map['text']), marks: marks);
      case 'math':
        if (map.containsKey('text')) reader.fail();
        return DocumentMath(reader.string(map['expression']), marks: marks);
      default:
        reader.fail();
    }
  }

  static DocumentBlock _decodeBlock(
    Object? raw,
    DocumentCodecReader reader,
    int depth,
  ) {
    if (++reader.blocks > 512 || depth > 8) reader.fail();
    final map = reader.object(
      raw,
      const {'id', 'type'},
      const {
        'runs',
        'children',
        'level',
        'checked',
        'icon',
        'tone',
        'rows',
        'headerRow',
        'headerColumn',
      },
    );
    final kind = DocumentBlockKind.values
        .where((value) => value.name == map['type'])
        .firstOrNull;
    if (kind == null) reader.fail();
    final table = kind == DocumentBlockKind.table;
    final divider = kind == DocumentBlockKind.divider;
    if (table || divider) {
      if (map.containsKey('runs') || map.containsKey('children')) reader.fail();
    } else if (!map.containsKey('runs')) {
      reader.fail();
    }
    if (kind != DocumentBlockKind.heading && map.containsKey('level') ||
        kind != DocumentBlockKind.todo && map.containsKey('checked') ||
        kind != DocumentBlockKind.callout &&
            (map.containsKey('icon') || map.containsKey('tone')) ||
        !table && ['rows', 'headerRow', 'headerColumn'].any(map.containsKey)) {
      reader.fail();
    }
    final tone = map.containsKey('tone')
        ? DocumentColor.values.where((c) => c.name == map['tone']).firstOrNull
        : null;
    if (map.containsKey('tone') && tone == null) reader.fail();
    return DocumentBlock(
      id: reader.string(map['id']),
      kind: kind,
      runs: table || divider ? const [] : _runs(map['runs'], reader),
      children: map.containsKey('children')
          ? [
              for (final child in reader.list(map['children'], 512))
                _decodeBlock(child, reader, depth + 1),
            ]
          : const [],
      level: map.containsKey('level') ? reader.integer(map['level']) : null,
      checked: map.containsKey('checked')
          ? reader.boolean(map['checked'])
          : null,
      icon: map.containsKey('icon') ? reader.string(map['icon']) : null,
      tone: tone,
      rows: table ? _rows(map['rows'], reader) : const [],
      headerRow: map.containsKey('headerRow')
          ? reader.boolean(map['headerRow'])
          : false,
      headerColumn: map.containsKey('headerColumn')
          ? reader.boolean(map['headerColumn'])
          : false,
    );
  }

  static List<DocumentRow> _rows(Object? raw, DocumentCodecReader reader) => [
    for (final value in reader.list(raw, 32)) _row(value, reader),
  ];

  static DocumentRow _row(Object? raw, DocumentCodecReader reader) {
    final map = reader.object(raw, const {'id', 'cells'});
    return DocumentRow(
      id: reader.string(map['id']),
      cells: [
        for (final value in reader.list(map['cells'], 12)) _cell(value, reader),
      ],
    );
  }

  static DocumentCell _cell(Object? raw, DocumentCodecReader reader) {
    if (++reader.cells > 512) reader.fail();
    final map = reader.object(raw, const {'id', 'runs'});
    return DocumentCell(
      id: reader.string(map['id']),
      runs: _runs(map['runs'], reader),
    );
  }
}
