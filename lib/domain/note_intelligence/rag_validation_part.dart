// Shared validation vocabulary of the RAG Domain contract.
part of 'rag_models.dart';

/// Identifier ceiling mirrored from the backend contract.
const int _maxIdentifierCodePoints = 128;

/// Builds the field/reason-only error every model refuses with.
///
/// The rejected value is deliberately not attached: `ArgumentError.value` would
/// echo a raw question, title, quote, or answer into `toString`, and a note body
/// or an answer must never leak through an exception. Only the contract field
/// and the reason travel.
ArgumentError _invalid(String field, String reason) =>
    ArgumentError('$field $reason');

String _requireQuestion(String question) {
  if (RagRequest.questionProblem(question) != null) {
    throw _invalid('question', 'is not a valid question');
  }
  return question;
}

String _requireIdentifier(String value, String fieldName) {
  if (value.isEmpty ||
      value.trim() != value ||
      !_isWellFormed(value) ||
      _hasAsciiControl(value) ||
      _codePointCount(value) > _maxIdentifierCodePoints) {
    throw _invalid(fieldName, 'is not a contract identifier');
  }
  return value;
}

String _requireWellFormed(String value, String fieldName) {
  if (!_isWellFormed(value)) {
    throw _invalid(fieldName, 'must be well-formed UTF-16');
  }
  return value;
}

int _requireRevision(int revision) {
  if (revision < 1) {
    throw _invalid('revision', 'must be at least 1');
  }
  return revision;
}

int _requireOffset(int offset, String fieldName) {
  if (offset < 0) {
    throw _invalid(fieldName, 'must not be negative');
  }
  return offset;
}

int _requireSpanEnd(int end, int start) {
  if (end <= start) {
    throw _invalid('endOffset', 'must be greater than startOffset');
  }
  return end;
}

String _requireQuote(
  String quote, {
  required int startOffset,
  required int endOffset,
}) {
  if (quote.isEmpty || !_isWellFormed(quote)) {
    throw _invalid('quote', 'must be non-empty well-formed UTF-16 text');
  }
  if (quote.length != endOffset - startOffset) {
    throw _invalid('quote', 'must be exactly endOffset - startOffset code units');
  }
  return quote;
}

String _requireAnswer(String answer) {
  if (answer.trim().isEmpty || !_isWellFormed(answer)) {
    throw _invalid('answer', 'must be non-empty well-formed UTF-16 text');
  }
  return answer;
}

String _requireReason(String reason) {
  if (!RagResult.reasons.contains(reason)) {
    throw _invalid('reason', 'is not a canonical verdict');
  }
  return reason;
}

List<RagSource> _freezeSources(
  Iterable<RagSource> sources, {
  required bool requireCitation,
}) {
  final List<RagSource> frozen = List<RagSource>.unmodifiable(sources);
  if (requireCitation && frozen.isEmpty) {
    throw _invalid('sources', 'an answer needs at least one citation');
  }
  final Set<String> seen = <String>{};
  for (final RagSource source in frozen) {
    if (!seen.add(source.sourceId)) {
      throw _invalid('sources', 'contains a duplicate sourceId');
    }
  }
  return frozen;
}

String _requireConsentVersion(String version) {
  if (version != RagConsent.currentVersion) {
    throw _invalid('version', 'is not the consent version');
  }
  return version;
}

int _requireGeneration(int generation, [String fieldName = 'generation']) {
  if (generation < 0) {
    throw _invalid(fieldName, 'must not be negative');
  }
  return generation;
}

bool _hasAsciiControl(String value) {
  for (int index = 0; index < value.length; index++) {
    final int unit = value.codeUnitAt(index);
    if (unit <= 0x1f || unit == 0x7f) {
      return true;
    }
  }
  return false;
}

/// A lone surrogate cannot survive UTF-8 egress; it is refused, never replaced.
bool _isWellFormed(String value) {
  for (int index = 0; index < value.length; index++) {
    final int unit = value.codeUnitAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (index + 1 >= value.length) {
        return false;
      }
      final int next = value.codeUnitAt(index + 1);
      if (next < 0xdc00 || next > 0xdfff) {
        return false;
      }
      index++;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

bool _isCodePointBoundary(String content, int index) {
  if (index <= 0 || index >= content.length) {
    return index >= 0 && index <= content.length;
  }
  final int before = content.codeUnitAt(index - 1);
  final int after = content.codeUnitAt(index);
  final bool highBefore = before >= 0xd800 && before <= 0xdbff;
  final bool lowAfter = after >= 0xdc00 && after <= 0xdfff;
  return !(highBefore && lowAfter);
}

int _codePointCount(String value) {
  int count = 0;
  for (int index = 0; index < value.length; index++) {
    final int unit = value.codeUnitAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff && index + 1 < value.length) {
      final int next = value.codeUnitAt(index + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        index++;
      }
    }
    count++;
  }
  return count;
}
