import 'summary_policy_test_support.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/infrastructure/note_intelligence/remote_summarization_service.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_api_failure.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_request_policy.dart';

/// One recorded stage generation call.
final class SummaryTestStageCall {
  SummaryTestStageCall({
    required this.stage,
    required this.inputs,
    required this.consentAccepted,
    required this.deadline,
  });

  final SummaryStage stage;
  final List<String> inputs;
  final bool consentAccepted;
  final DateTime? deadline;
}

/// Records every stage call and answers from a per-test responder.
final class SummaryTestGenerator {
  SummaryTestGenerator(this._respond);

  final Future<String> Function(SummaryTestStageCall call) _respond;
  final List<SummaryTestStageCall> calls = <SummaryTestStageCall>[];

  List<SummaryStage> get stages => calls
      .map((SummaryTestStageCall call) => call.stage)
      .toList(growable: false);

  Future<String> call({
    required SummaryStage stage,
    required List<String> inputs,
    required bool consentAccepted,
    DateTime? deadline,
  }) {
    final SummaryTestStageCall recorded = SummaryTestStageCall(
      stage: stage,
      inputs: List<String>.of(inputs),
      consentAccepted: consentAccepted,
      deadline: deadline,
    );
    calls.add(recorded);
    return _respond(recorded);
  }
}

/// Session consent double; [decide] receives the 1-based check number.
final class SummaryTestConsent {
  SummaryTestConsent([this.decide]);

  final bool Function(int check)? decide;
  int checks = 0;

  bool call() {
    checks++;
    return decide?.call(checks) ?? true;
  }
}

Matcher failsWith(SummaryApiErrorCode code) => throwsA(
  isA<SummaryApiFailure>().having(
    (SummaryApiFailure failure) => failure.code,
    'code',
    code,
  ),
);

RemoteSummarizationService remoteService(
  SummaryRequestPolicy policy,
  SummaryTestGenerator generator, {
  SummaryTestConsent? consent,
  Duration timeout = RemoteSummarizationService.maxPipelineTimeout,
}) => RemoteSummarizationService(
  policy: policy,
  generate: generator.call,
  hasConsent: (consent ?? SummaryTestConsent()).call,
  pipelineTimeout: timeout,
);

/// Largest ASCII content length, up to 4096, that still fits one [stage] call.
///
/// Measured with the policy itself instead of duplicating its formula, so the
/// tests follow the bundled asset rather than a hardcoded estimate. Only the
/// small test policy, whose capacity is far below the bound, relies on it.
int sectionCapacity(SummaryRequestPolicy policy, SummaryStage stage) {
  int low = 1;
  int high = 4096;
  while (low < high) {
    final int mid = low + (high - low + 1) ~/ 2;
    if (policy.fitsInput(stage, <String>['a' * mid])) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return low;
}

Future<SummaryRequestPolicy> policyWith(
  void Function(Map<String, dynamic> data) mutate,
) async {
  final Map<String, dynamic> data =
      jsonDecode(await summaryTestPolicyJson()) as Map<String, dynamic>;
  mutate(data);
  return SummaryRequestPolicy.fromJson(jsonEncode(data));
}

/// ASCII content whose `direct` estimate is exactly [estimate].
String directContentAt(SummaryRequestPolicy policy, int estimate) {
  final int one = policy.estimateInputTokens(SummaryStage.direct, <String>[
    'a',
  ]);
  // One ASCII character moves the rendered JSON by exactly one UTF-8 byte.
  return 'a' * (estimate - one + 1);
}

/// Fails when a chunk boundary cuts a valid surrogate pair.
void expectNoSplitPairs(List<String> chunks, String source) {
  int offset = 0;
  for (final String chunk in chunks) {
    final int end = offset + chunk.length;
    if (chunk.isNotEmpty && end < source.length) {
      final int last = chunk.codeUnitAt(chunk.length - 1);
      final int next = source.codeUnitAt(end);
      final bool cutsPair =
          last >= 0xD800 && last <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF;
      expect(cutsPair, isFalse, reason: 'split a surrogate pair at $end');
    }
    offset = end;
  }
}
