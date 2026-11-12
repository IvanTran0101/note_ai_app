import 'dart:async';
import 'dart:convert';

import '../../domain/note_intelligence/i_note_summarization_service.dart';
import '../../domain/note_intelligence/summary.dart';

import 'summary_api_failure.dart';
import 'summary_chunk_splitter.dart';
import 'summary_http_gateway.dart';
import 'summary_request_policy.dart';

/// [INoteSummarizationService] backed by the remote Summary Cloud pipeline.
///
/// The orchestrator owns what the transport deliberately does not: the
/// direct-versus-chunked decision, the ordered section calls, the single merge,
/// the policy's generation-call ceiling, one deadline for the whole pipeline,
/// and the consent rechecks. One [generate] call is one generation; this class
/// never retries, never merges recursively, and never adds a direct call after
/// a merge.
///
/// Failure is all-or-nothing: a failing stage stops the pipeline before the
/// next call, and a result that arrives after the deadline is discarded, so the
/// caller receives either the final summary text or a [SummaryApiFailure] -
/// never a partial summary.
///
/// Account and note-snapshot context (ownership, saved state, conflicts) belongs
/// to a later phase. [hasConsent] is the session hook this phase needs; it is
/// re-read before every stage and again before a result is accepted, so a
/// session that revokes consent mid-pipeline cannot receive a summary.
final class RemoteSummarizationService implements INoteSummarizationService {
  /// Creates the orchestrator over [policy], [generate], and [hasConsent].
  ///
  /// [pipelineTimeout] is the deadline for the whole operation, shared by every
  /// stage; it defaults to and never exceeds [maxPipelineTimeout]. [generate] is
  /// the transport seam and must fail with [SummaryApiFailure].
  RemoteSummarizationService({
    required this.policy,
    required this.generate,
    required this.hasConsent,
    Duration pipelineTimeout = maxPipelineTimeout,
  }) : pipelineTimeout = _validatePipelineTimeout(pipelineTimeout);

  /// Contract ceiling for one whole pipeline (150 s).
  static const Duration maxPipelineTimeout = Duration(seconds: 150);

  /// Shared prompts, budgets, and the consent version.
  final SummaryRequestPolicy policy;

  /// One stage generation; `SummaryHttpGateway.generate` fits this seam.
  final SummaryStageGenerator generate;

  /// Whether the current session still allows sending note content.
  final bool Function() hasConsent;

  /// Deadline for the whole pipeline, measured from the start of [summarize].
  final Duration pipelineTimeout;

  /// Built once from [policy]; lazy so the constructor stays field assignment.
  late final SummaryChunkSplitter _splitter = SummaryChunkSplitter(policy);

  @override
  Future<Summary> summarize(String content) async {
    // One clock read for the whole run: every stage receives the same absolute
    // deadline, so a slow early stage shortens the later ones instead of each
    // stage restarting its own budget.
    final DateTime deadline = DateTime.now().add(pipelineTimeout);
    final String note = SummaryRequestPolicy.normalizeInput(content);
    if (note.isEmpty) {
      throw const SummaryApiFailure(code: SummaryApiErrorCode.invalidInput);
    }
    _requireConsent();

    if (_splitter.fitsDirect(note)) {
      final String text = await _run(SummaryStage.direct, <String>[
        note,
      ], deadline);
      _requireConsent();
      return Summary(_requireText(text));
    }

    // Preflight the whole plan before the first generation: chunk count, each
    // chunk's fit, and the call ceiling are settled while zero calls are spent.
    final List<String> chunks = _splitter.split(note);
    if (chunks.length + 1 > policy.maxGenerationCalls) {
      // The ceiling is policy-owned: `maxChunks` section calls plus one merge.
      // `split` already bounds the chunk count, so this only fails if a future
      // stage is added without revisiting the budget.
      throw const SummaryApiFailure(code: SummaryApiErrorCode.pipelineTooLarge);
    }

    for (final String chunk in chunks) {
      _checkBody(SummaryStage.section, <String>[chunk]);
    }
    final List<String> sections = <String>[];
    for (final String chunk in chunks) {
      final String text = await _run(SummaryStage.section, <String>[
        chunk,
      ], deadline);
      sections.add(_requireText(text));
    }

    if (!_splitter.fitsMerge(sections)) {
      // The contract forbids splitting the merge further or recursing into
      // another merge; this pipeline cannot finish inside its budget.
      throw const SummaryApiFailure(code: SummaryApiErrorCode.pipelineTooLarge);
    }
    final String merged = await _run(SummaryStage.merge, sections, deadline);
    _requireConsent();
    return Summary(_requireText(merged));
  }

  /// Runs one stage: deadline and consent first, the call, deadline again - so
  /// a result that arrived after the deadline is never used or followed.
  Future<String> _run(
    SummaryStage stage,
    List<String> inputs,
    DateTime deadline,
  ) async {
    _checkDeadline(deadline);
    _requireConsent();
    _checkBody(stage, inputs);
    _checkDeadline(deadline);
    final String text;
    try {
      text = await generate(
        stage: stage,
        inputs: inputs,
        consentAccepted: true,
        deadline: deadline,
      ).timeout(deadline.difference(DateTime.now()));
    } on TimeoutException {
      throw const SummaryApiFailure(code: SummaryApiErrorCode.timeout);
    }
    _checkDeadline(deadline);
    return text;
  }

  /// Rejects a stage result that is blank under the policy's ECMAScript trim.
  ///
  /// The gateway validates this too; the check stays here so an injected
  /// generator cannot send an empty section into the merge or return an empty
  /// summary.
  static String _requireText(String text) {
    if (SummaryRequestPolicy.normalizeInput(text).isEmpty) {
      throw const SummaryApiFailure(code: SummaryApiErrorCode.invalidOutput);
    }
    return text;
  }

  void _checkBody(SummaryStage stage, List<String> inputs) {
    if (utf8.encode(policy.requestJson(stage, inputs)).length >
        policy.maxBodyBytesUtf8) {
      throw const SummaryApiFailure(code: SummaryApiErrorCode.inputTooLong);
    }
  }

  void _requireConsent() {
    if (!hasConsent()) {
      throw const SummaryApiFailure(code: SummaryApiErrorCode.consentRequired);
    }
  }

  static void _checkDeadline(DateTime deadline) {
    if (!DateTime.now().isBefore(deadline)) {
      throw const SummaryApiFailure(code: SummaryApiErrorCode.timeout);
    }
  }

  static Duration _validatePipelineTimeout(Duration timeout) {
    if (timeout <= Duration.zero || timeout > maxPipelineTimeout) {
      throw ArgumentError(
        'Summary pipeline timeout must be above zero and at most 150 s',
      );
    }
    return timeout;
  }
}
