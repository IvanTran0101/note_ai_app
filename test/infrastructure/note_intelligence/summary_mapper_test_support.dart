import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_api_failure.dart';

/// Matches a [SummaryApiFailure] carrying [code].
Matcher throwsCode(SummaryApiErrorCode code) => throwsA(
  isA<SummaryApiFailure>().having(
    (SummaryApiFailure failure) => failure.code,
    'code',
    code,
  ),
);

Uint8List bytes(String value) => Uint8List.fromList(utf8.encode(value));

Uint8List rawBytes(List<int> value) => Uint8List.fromList(value);

String successBody({
  Object? summary = 'Bản tóm tắt nội dung',
  Object? requestId = 'req-7f3a',
  Object? usage = const <String, Object?>{
    'inputTokens': 1200,
    'outputTokens': 95,
  },
  Map<String, Object?> extra = const <String, Object?>{},
}) => jsonEncode(<String, Object?>{
  'summary': summary,
  'requestId': requestId,
  'usage': usage,
  ...extra,
});
