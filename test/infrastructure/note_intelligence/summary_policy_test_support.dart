import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_request_policy.dart';

// Chrome's unit-test harness cannot read bundled assets (Flutter #159879).
// Inject bytes from the source asset for mocks; native tests read the bundle.
Future<String> summaryTestPolicyJson() async {
  const String encoded = String.fromEnvironment('SUMMARY_TEST_POLICY_BASE64');
  return encoded.isEmpty
      ? rootBundle.loadString(SummaryRequestPolicy.assetPath)
      : utf8.decode(base64Decode(encoded));
}

Future<SummaryRequestPolicy> loadSummaryTestPolicy() async =>
    SummaryRequestPolicy.fromJson(await summaryTestPolicyJson());
