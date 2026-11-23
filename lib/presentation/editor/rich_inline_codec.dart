import 'package:appflowy_editor/appflowy_editor.dart' as engine;

import '../../domain/notes/note_document.dart';

/// Transient engine attributes. Only pure business marks cross into snapshots.
abstract final class RichInlineCodec {
  static Map<String, dynamic> attributes(DocumentMarks marks) => {
    if (marks.bold) 'bold': true,
    if (marks.italic) 'italic': true,
    if (marks.underline) 'underline': true,
    if (marks.strikethrough) 'strikethrough': true,
    if (marks.inlineCode) 'code': true,
    if (marks.fontSize != null) 'font_size': marks.fontSize,
    if (marks.link != null) 'href': marks.link,
    if (marks.color != null) 'm09_color': marks.color!.name,
    if (marks.highlight != null) 'm09_highlight': marks.highlight!.name,
  };

  static DocumentColor? color(Object? value) {
    if (value == null) return null;
    for (final color in DocumentColor.values) {
      if (color.name == value) return color;
    }
    throw StateError('Invalid editor color.');
  }

  static DocumentMarks marks(Map<String, dynamic>? raw) {
    final data = raw ?? const <String, dynamic>{};
    return DocumentMarks(
      bold: data['bold'] == true,
      italic: data['italic'] == true,
      underline: data['underline'] == true,
      strikethrough: data['strikethrough'] == true,
      inlineCode: data['code'] == true,
      fontSize: (data['font_size'] as num?)?.toDouble(),
      link: data['href'] as String?,
      color: color(data['m09_color']),
      highlight: color(data['m09_highlight']),
    );
  }

  static engine.Delta encode(Iterable<DocumentInline> runs) {
    final delta = engine.Delta();
    for (final run in runs) {
      delta.insert(
        run is DocumentMath ? '\uFFFC' : (run as DocumentText).text,
        attributes: {
          ...attributes(run.marks),
          if (run is DocumentMath) 'm09_math': run.expression,
        },
      );
    }
    return delta;
  }

  static List<DocumentInline> decode(engine.Delta? delta) => [
    if (delta != null)
      for (final operation in delta) ..._runs(operation),
  ];

  static Iterable<DocumentInline> _runs(engine.TextOperation operation) sync* {
    if (operation is! engine.TextInsert) {
      throw StateError('Document contains a non-insert delta.');
    }
    final formatting = marks(operation.attributes);
    final expression = operation.attributes?['m09_math'];
    if (expression == null) {
      yield DocumentText(operation.text, marks: formatting);
      return;
    }
    if (expression is! String ||
        operation.text.codeUnits.any((c) => c != 0xFFFC)) {
      throw StateError('Invalid editor equation atom.');
    }
    for (var i = 0; i < operation.text.length; i++) {
      yield DocumentMath(expression, marks: formatting);
    }
  }
}
