import 'note_summary_resource_policy.dart';
import 'summary_api_failure.dart';
import 'summary_request_policy.dart';

/// Preflights one normalized note into the ordered chunks the remote pipeline
/// sends, before the first generation call.
///
/// The splitter is the only place that divides note text for the remote path,
/// and it fails closed: [split] either returns a complete ordered plan or
/// throws [SummaryApiErrorCode.pipelineTooLarge], so the orchestrator never
/// spends a generation call on a pipeline the policy cannot finish.
///
/// Chunks are UTF-16 substrings of the normalized note, so joining them in
/// order reproduces that note exactly - boundary whitespace included, because
/// the backend trims each request's edges itself. A boundary never splits a
/// valid surrogate pair and lone surrogate code units survive unchanged. Every
/// chunk is non-blank under the policy's ECMAScript trim, since a blank input is
/// a request the backend rejects.
///
/// Sizing uses the policy's own fully rendered `section` estimate - messages
/// JSON, escaping, and UTF-8 bytes included - never a character or token ratio,
/// and never the local model's 2-character heuristic.
final class SummaryChunkSplitter {
  /// Creates a splitter over [policy].
  const SummaryChunkSplitter(this._policy);

  final SummaryRequestPolicy _policy;

  /// Whether [normalized] fits one `direct` call.
  bool fitsDirect(String normalized) =>
      _fits(SummaryStage.direct, <String>[normalized]);

  /// Whether the ordered [sections] fit the one `merge` call.
  bool fitsMerge(List<String> sections) => _fits(SummaryStage.merge, sections);

  /// Splits a note that did not fit `direct` into 2..`maxChunks` chunks.
  ///
  /// The largest prefix that fits one `section` call is found by binary search,
  /// then pulled back to the highest newline, the highest whitespace, or a
  /// rune-safe hard split, in that order.
  ///
  /// @throws SummaryApiFailure [SummaryApiErrorCode.invalidInput] for blank
  /// input, and [SummaryApiErrorCode.pipelineTooLarge] when the note needs more
  /// chunks than the policy allows, when one rune cannot fit a section call, or
  /// when the note has no valid pipeline at all. Nothing is truncated.
  List<String> split(String normalized) {
    final int length = normalized.length;
    if (length == 0 ||
        SummaryRequestPolicy.normalizeInput(normalized).isEmpty) {
      throw const SummaryApiFailure(code: SummaryApiErrorCode.invalidInput);
    }
    if (_fitsSection(normalized)) {
      // A whole note that fits one `section` call but not one `direct` call has
      // no valid pipeline: the contract's merge stage takes 2..maxChunks
      // ordered section outputs, so a section-only result is not a summary.
      throw _pipelineTooLarge;
    }

    final List<String> chunks = <String>[];
    int start = 0;
    while (start < length) {
      final int contentStart = _firstContentIndex(normalized, start);
      if (contentStart < 0) {
        // Only whitespace remains; no request can be built from it.
        throw _pipelineTooLarge;
      }
      final int floor = _runeEndAt(normalized, contentStart + 1);
      if (!_fitsSection(normalized.substring(start, floor))) {
        // One rune, plus the whitespace in front of it, already exceeds one
        // section call.
        throw _pipelineTooLarge;
      }

      int end;
      if (_fitsSection(normalized.substring(start, length))) {
        end = length;
      } else {
        end = _avoidSurrogateSplit(
          normalized,
          start,
          _largestFittingEnd(normalized, start, floor, length),
        );
        final int boundary = chooseSummaryChunkBoundary(
          start: start,
          end: end,
          unitAt: normalized.codeUnitAt,
        );
        // A boundary that leaves a blank chunk fails this fit check, because
        // the policy refuses an input that is empty after its trim.
        if (_fitsSection(normalized.substring(start, boundary))) {
          end = boundary;
        }
      }

      final String chunk = normalized.substring(start, end);
      if (!_fitsSection(chunk)) {
        // The checks above make this unreachable; it stays so a later edit
        // cannot emit a request the policy would refuse.
        throw _pipelineTooLarge;
      }
      chunks.add(chunk);
      if (chunks.length > _policy.maxChunks) {
        throw _pipelineTooLarge;
      }
      start = end;
    }
    if (chunks.length < 2) {
      throw _pipelineTooLarge;
    }
    return List<String>.unmodifiable(chunks);
  }

  /// The largest end in `[floor, length - 1]` whose chunk fits a section call.
  ///
  /// The caller has already established that [floor] fits and that the whole
  /// remainder does not, so both ends of the search are known. Each probe
  /// renders only its candidate substring, which keeps the search O(n log n)
  /// rather than re-rendering the whole note per step.
  int _largestFittingEnd(String note, int start, int floor, int length) {
    int low = floor;
    int high = length - 1;
    while (low < high) {
      final int mid = _runeEndAt(note, low + (high - low + 1) ~/ 2);
      if (_fitsSection(note.substring(start, mid))) {
        low = mid;
      } else {
        high = _avoidSurrogateSplit(note, start, mid - 1);
      }
    }
    return low;
  }

  bool _fitsSection(String text) => _fits(SummaryStage.section, <String>[text]);

  bool _fits(SummaryStage stage, List<String> inputs) {
    try {
      return _policy.fitsInput(stage, inputs);
    } on ArgumentError {
      // The policy refuses a blank input or a wrong input count. Treat that as
      // "does not fit" so every refusal above stays a safe SummaryApiFailure.
      return false;
    }
  }

  /// The first index at or after [start] holding a non-whitespace code unit, or
  /// `-1` when only whitespace remains.
  static int _firstContentIndex(String note, int start) {
    for (int index = start; index < note.length; index++) {
      if (!SummaryRequestPolicy.isInputWhitespace(note.codeUnitAt(index))) {
        return index;
      }
    }
    return -1;
  }

  /// [end] extended by one code unit when that keeps a valid surrogate pair
  /// whole.
  static int _runeEndAt(String note, int end) {
    if (end > 0 &&
        end < note.length &&
        _isHighSurrogate(note.codeUnitAt(end - 1)) &&
        _isLowSurrogate(note.codeUnitAt(end))) {
      return end + 1;
    }
    return end;
  }

  /// [end] pulled back by one code unit when it would cut a valid surrogate
  /// pair. Never returns a value below `start + 1`: the caller's floor is
  /// already rune-aligned.
  static int _avoidSurrogateSplit(String note, int start, int end) {
    if (end > start + 1 &&
        end < note.length &&
        _isHighSurrogate(note.codeUnitAt(end - 1)) &&
        _isLowSurrogate(note.codeUnitAt(end))) {
      return end - 1;
    }
    return end;
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  static bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
}

const SummaryApiFailure _pipelineTooLarge = SummaryApiFailure(
  code: SummaryApiErrorCode.pipelineTooLarge,
);
