import 'dart:convert';

enum DocumentColor {
  gray,
  brown,
  orange,
  yellow,
  green,
  blue,
  purple,
  pink,
  red,
}

/// Business formatting values; no theme colors, pixels or editor objects.
final class DocumentMarks {
  const DocumentMarks.plain()
    : bold = false,
      italic = false,
      underline = false,
      strikethrough = false,
      inlineCode = false,
      color = null,
      highlight = null,
      fontSize = null,
      link = null;

  factory DocumentMarks({
    bool bold = false,
    bool italic = false,
    bool underline = false,
    bool strikethrough = false,
    bool inlineCode = false,
    DocumentColor? color,
    DocumentColor? highlight,
    double? fontSize,
    String? link,
  }) {
    if (fontSize != null &&
        (!fontSize.isFinite || fontSize < 12 || fontSize > 48)) {
      throw ArgumentError('Document font size must be between12 and48.');
    }
    if (link != null) _validateLink(link);
    return DocumentMarks._(
      bold,
      italic,
      underline,
      strikethrough,
      inlineCode,
      color,
      highlight,
      fontSize,
      link,
    );
  }
  const DocumentMarks._(
    this.bold,
    this.italic,
    this.underline,
    this.strikethrough,
    this.inlineCode,
    this.color,
    this.highlight,
    this.fontSize,
    this.link,
  );

  final bool bold, italic, underline, strikethrough, inlineCode;
  final DocumentColor? color, highlight;
  final double? fontSize;
  final String? link;

  @override
  bool operator ==(Object other) =>
      other is DocumentMarks &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.strikethrough == strikethrough &&
      other.inlineCode == inlineCode &&
      other.color == color &&
      other.highlight == highlight &&
      other.fontSize == fontSize &&
      other.link == link;
  @override
  int get hashCode => Object.hash(
    bold,
    italic,
    underline,
    strikethrough,
    inlineCode,
    color,
    highlight,
    fontSize,
    link,
  );
}

void _validateLink(String value) {
  // URLs accepted here are user actions, never automatically fetched resources.
  if (utf8.encode(value).length > 2048 ||
      value.trim() != value ||
      RegExp(r'[\x00-\x20\x7f]').hasMatch(value)) {
    throw ArgumentError('Invalid document link.');
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !['https', 'http', 'mailto'].contains(uri.scheme) ||
      (uri.scheme == 'mailto' ? uri.path.isEmpty : uri.host.isEmpty)) {
    throw ArgumentError('Unsupported document link.');
  }
}
