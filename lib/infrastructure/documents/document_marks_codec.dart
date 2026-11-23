import '../../domain/notes/note_document.dart';
import 'document_codec_reader.dart';

abstract final class DocumentMarksCodec {
  static Map<String, Object?> encode(DocumentMarks marks) => {
    if (marks.bold) 'bold': true,
    if (marks.italic) 'italic': true,
    if (marks.underline) 'underline': true,
    if (marks.strikethrough) 'strikethrough': true,
    if (marks.inlineCode) 'inlineCode': true,
    if (marks.color != null) 'color': marks.color!.name,
    if (marks.highlight != null) 'highlight': marks.highlight!.name,
    if (marks.fontSize != null) 'fontSize': marks.fontSize,
    if (marks.link != null) 'link': marks.link,
  };

  static DocumentMarks decode(Object? raw, DocumentCodecReader reader) {
    final map = reader.object(raw, const {}, const {
      'bold',
      'italic',
      'underline',
      'strikethrough',
      'inlineCode',
      'color',
      'highlight',
      'fontSize',
      'link',
    });
    bool flag(String key) =>
        map.containsKey(key) ? reader.boolean(map[key]) : false;
    DocumentColor? color(String key) {
      if (!map.containsKey(key)) return null;
      final name = reader.string(map[key]);
      for (final value in DocumentColor.values) {
        if (value.name == name) return value;
      }
      reader.fail();
    }

    final size = map['fontSize'];
    if (map.containsKey('fontSize') && size is! num) reader.fail();
    return DocumentMarks(
      bold: flag('bold'),
      italic: flag('italic'),
      underline: flag('underline'),
      strikethrough: flag('strikethrough'),
      inlineCode: flag('inlineCode'),
      color: color('color'),
      highlight: color('highlight'),
      fontSize: size == null ? null : (size as num).toDouble(),
      link: map.containsKey('link') ? reader.string(map['link']) : null,
    );
  }
}
