/// Strict JSON hygiene for the small, untrusted Phase 5 RAG envelopes.
///
/// The frozen contract refuses a body with a duplicate object key (raw or
/// `\u`-escaped) and a body that nests past `MAX_JSON_DEPTH`: `jsonDecode` keeps
/// the last duplicate, and an unbounded nesting depth can exhaust the stack on a
/// hostile 64 KiB payload. The scanner mirrors the backend's exported
/// `assertNoDuplicateKeys` (`amplify/rag/contract.ts`) so both ends of the wire
/// refuse the same bodies.
///
/// It is a scanner, not a second parser: anything it cannot follow is left to
/// `jsonDecode`, which keeps the only syntax verdict.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Maximum object/array nesting one RAG envelope may use (`MAX_JSON_DEPTH`).
const int ragMaxJsonDepth = 32;

/// Why a body could not be handed to the strict envelope reader.
///
/// The reason is one of four fixed words and never carries the payload, so a
/// rejection can be reported without echoing a note, an answer, or a token.
final class RagJsonProblem implements Exception {
  /// Creates a problem with a fixed reason.
  const RagJsonProblem(this.reason);

  /// `not-utf8`, `duplicate-key`, `too-deep`, or `malformed`.
  final String reason;

  @override
  String toString() => 'RagJsonProblem($reason)';
}

/// Decodes one UTF-8 JSON body under the contract's duplicate and depth rules.
///
/// Throws [RagJsonProblem] for malformed UTF-8, a duplicate key, nesting past
/// [ragMaxJsonDepth], or invalid JSON. The decoded value is unvalidated: the
/// caller still checks the exact envelope it expects.
Object? decodeRagJson(Uint8List bodyBytes) {
  final String text;
  try {
    // Strict on purpose: a body that is not valid UTF-8 is never replaced into
    // a valid-looking one.
    text = utf8.decode(bodyBytes);
  } on FormatException {
    throw const RagJsonProblem('not-utf8');
  }
  assertNoDuplicateKeys(text);
  try {
    return jsonDecode(text);
  } on FormatException {
    throw const RagJsonProblem('malformed');
  }
}

/// Refuses duplicate object keys after escape decoding and nesting past
/// [ragMaxJsonDepth]; malformed JSON is left to `jsonDecode`.
void assertNoDuplicateKeys(String text) {
  final List<_JsonFrame> stack = <_JsonFrame>[];
  int index = 0;

  void skipWhitespace() {
    while (index < text.length && _isWhitespace(text.codeUnitAt(index))) {
      index++;
    }
  }

  String? readString() {
    final int start = index;
    index++;
    while (index < text.length) {
      final int unit = text.codeUnitAt(index);
      if (unit == _quote) {
        index++;
        return _decodeStringToken(text.substring(start, index));
      }
      index += unit == _backslash ? 2 : 1;
    }
    return null;
  }

  bool readValue() {
    skipWhitespace();
    if (index >= text.length) {
      return false;
    }
    final int unit = text.codeUnitAt(index);
    if (unit == _openBrace || unit == _openBracket) {
      if (stack.length >= ragMaxJsonDepth) {
        throw const RagJsonProblem('too-deep');
      }
      stack.add(_JsonFrame(unit == _openBrace));
      index++;
      return true;
    }
    if (unit == _quote) {
      return readString() != null;
    }
    final int start = index;
    while (index < text.length && !_isDelimiter(text.codeUnitAt(index))) {
      index++;
    }
    return index > start;
  }

  while (index < text.length) {
    skipWhitespace();
    if (index >= text.length) {
      return;
    }
    if (stack.isEmpty) {
      if (!readValue()) {
        return;
      }
      if (stack.isEmpty) {
        return; // A scalar root: nothing left to scan.
      }
      continue;
    }
    final _JsonFrame frame = stack.last;
    final int unit = text.codeUnitAt(index);
    if (frame.isObject) {
      if (frame.state == 0) {
        if (unit == _closeBrace) {
          index++;
          stack.removeLast();
          continue;
        }
        final String? key = readString();
        if (key == null) {
          return; // Not a decodable string token: leave the verdict to jsonDecode.
        }
        if (!frame.keys!.add(key)) {
          throw const RagJsonProblem('duplicate-key');
        }
        frame.state = 1;
        continue;
      }
      if (frame.state == 1) {
        if (unit != _colon) {
          return;
        }
        index++;
        frame.state = 2;
        continue;
      }
      if (frame.state == 2) {
        if (!readValue()) {
          return;
        }
        frame.state = 3;
        continue;
      }
      if (unit == _comma) {
        index++;
        frame.state = 0;
        continue;
      }
      if (unit == _closeBrace) {
        index++;
        stack.removeLast();
        continue;
      }
      return;
    }
    if (frame.state == 0) {
      if (unit == _closeBracket) {
        index++;
        stack.removeLast();
        continue;
      }
      if (!readValue()) {
        return;
      }
      frame.state = 1;
      continue;
    }
    if (unit == _comma) {
      index++;
      frame.state = 0;
      continue;
    }
    if (unit == _closeBracket) {
      index++;
      stack.removeLast();
      continue;
    }
    return;
  }
}

/// One object or array frame of the scanner; `state` mirrors the backend's.
final class _JsonFrame {
  _JsonFrame(this.isObject) : keys = isObject ? <String>{} : null;

  final bool isObject;
  final Set<String>? keys;
  int state = 0;
}

/// Decodes one JSON string token, or null when it is not a valid string.
String? _decodeStringToken(String token) {
  try {
    final Object? decoded = jsonDecode(token);
    return decoded is String ? decoded : null;
  } on FormatException {
    return null;
  }
}

const int _quote = 0x22;
const int _backslash = 0x5c;
const int _colon = 0x3a;
const int _comma = 0x2c;
const int _openBrace = 0x7b;
const int _closeBrace = 0x7d;
const int _openBracket = 0x5b;
const int _closeBracket = 0x5d;

bool _isWhitespace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d;

bool _isDelimiter(int unit) =>
    _isWhitespace(unit) ||
    unit == _comma ||
    unit == _closeBrace ||
    unit == _closeBracket;
