import 'document_marks.dart';
import 'document_math.dart';

sealed class DocumentInline {
  const DocumentInline(this.marks);
  final DocumentMarks marks;
  String get plainText;
}

final class DocumentText extends DocumentInline {
  const DocumentText(
    this.text, {
    DocumentMarks marks = const DocumentMarks.plain(),
  }) : super(marks);
  final String text;
  @override
  String get plainText => text;
  @override
  bool operator ==(Object other) =>
      other is DocumentText && other.text == text && other.marks == marks;
  @override
  int get hashCode => Object.hash(text, marks);
}

final class DocumentMath extends DocumentInline {
  factory DocumentMath(
    String expression, {
    DocumentMarks marks = const DocumentMarks.plain(),
  }) {
    validateDocumentMath(expression);
    if (marks.link != null || marks.inlineCode) {
      throw ArgumentError('Equation cannot be a link or inline code.');
    }
    return DocumentMath._(expression, marks);
  }
  const DocumentMath._(this.expression, DocumentMarks marks) : super(marks);
  final String expression;
  @override
  String get plainText => expression;
  @override
  bool operator ==(Object other) =>
      other is DocumentMath &&
      other.expression == expression &&
      other.marks == marks;
  @override
  int get hashCode => Object.hash(expression, marks);
}

List<DocumentInline> freezeDocumentRuns(Iterable<DocumentInline> runs) {
  final result = <DocumentInline>[];
  StringBuffer? text;
  DocumentMarks? marks;
  void flush() {
    if (text != null && text!.isNotEmpty) {
      result.add(DocumentText(text.toString(), marks: marks!));
    }
    text = null;
  }

  for (final run in runs) {
    if (run is DocumentText) {
      if (text == null || marks != run.marks) {
        flush();
        text = StringBuffer();
        marks = run.marks;
      }
      text!.write(run.text);
    } else {
      flush();
      result.add(run);
    }
  }
  flush();
  return List.unmodifiable(result);
}
