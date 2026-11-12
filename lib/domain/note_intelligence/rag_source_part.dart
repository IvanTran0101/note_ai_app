// Approved citation of one answered result.
part of 'rag_models.dart';

/// One approved citation of an answered result.
///
/// Offsets are half-open UTF-16 code-unit spans into the note content:
/// `content.substring(startOffset, endOffset)` is exactly [quote]. A span that
/// starts or ends inside a surrogate pair, or a quote that is not exactly
/// `endOffset - startOffset` code units long, is refused at construction.
final class RagSource {
  /// Creates a validated citation.
  RagSource({
    required String sourceId,
    required String noteId,
    required int revision,
    required String title,
    required int startOffset,
    required int endOffset,
    required String quote,
  }) : sourceId = _requireIdentifier(sourceId, 'sourceId'),
       noteId = _requireIdentifier(noteId, 'noteId'),
       revision = _requireRevision(revision),
       title = _requireWellFormed(title, 'title'),
       startOffset = _requireOffset(startOffset, 'startOffset'),
       endOffset = _requireSpanEnd(endOffset, startOffset),
       quote = _requireQuote(
         quote,
         startOffset: startOffset,
         endOffset: endOffset,
       );

  /// The backend source identity; unique inside one result.
  final String sourceId;

  /// The canonical note id this citation points at.
  final String noteId;

  /// The server revision the citation was taken from; never 0.
  final int revision;

  /// The note title as the backend reported it.
  final String title;

  /// Inclusive start of the half-open UTF-16 span.
  final int startOffset;

  /// Exclusive end of the half-open UTF-16 span.
  final int endOffset;

  /// The exact text of the span.
  final String quote;

  /// Whether this span is a well-formed half-open range inside [content] whose
  /// exact slice equals [quote].
  ///
  /// Both boundaries must fall on a code-point boundary, so a span can never
  /// bisect a surrogate pair (the backend refuses that too).
  bool matchesContent(String content) {
    if (startOffset < 0 ||
        endOffset > content.length ||
        endOffset <= startOffset) {
      return false;
    }
    if (!_isCodePointBoundary(content, startOffset) ||
        !_isCodePointBoundary(content, endOffset)) {
      return false;
    }
    return content.substring(startOffset, endOffset) == quote;
  }

  @override
  bool operator ==(Object other) =>
      other is RagSource &&
      other.sourceId == sourceId &&
      other.noteId == noteId &&
      other.revision == revision &&
      other.title == title &&
      other.startOffset == startOffset &&
      other.endOffset == endOffset &&
      other.quote == quote;

  @override
  int get hashCode => Object.hash(
    sourceId,
    noteId,
    revision,
    title,
    startOffset,
    endOffset,
    quote,
  );

  @override
  String toString() {
    return 'RagSource(sourceId: $sourceId, noteId: $noteId, '
        'revision: $revision, span: [$startOffset, $endOffset))';
  }
}
