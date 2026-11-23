import 'dart:convert';
import 'dart:math';

import '../../application/notes/note_application.dart';
import 'summary_api_failure.dart';
import 'summary_request_policy.dart';

/// Private transport context for one pipeline; contains no unlock grant.
final class SummaryNoteLineage {
  SummaryNoteLineage(this.context)
    : runId = base64UrlEncode(
        List<int>.generate(24, (_) => Random.secure().nextInt(256)),
      );
  final SummaryRunContext context;
  final String runId;
  int _index = 0;
  int _end = 0;

  Map<String, Object?> forStage(SummaryStage stage, List<String> inputs) {
    int? start, end;
    if (stage == SummaryStage.section) {
      final text = SummaryRequestPolicy.normalizeInput(
        context.noteSnapshot.content,
      );
      final chunk = SummaryRequestPolicy.normalizeInput(inputs.single);
      start = text.indexOf(chunk, _end);
      if (start < 0) {
        throw const SummaryApiFailure(code: SummaryApiErrorCode.noteChanged);
      }
      end = start + chunk.length;
      _end = end;
    }
    final note = context.noteSnapshot;
    return {
      'ownerId': note.ownerId,
      if (note.share != null) 'accessRevision': note.share!.accessRevision,
      'noteId': note.id,
      'contentRevision': note.contentRevision,
      'protectionRevision': note.protectionRevision,
      'runId': runId,
      'sectionIndex': _index++,
      'sourceStart': start,
      'sourceEnd': end,
    };
  }
}
