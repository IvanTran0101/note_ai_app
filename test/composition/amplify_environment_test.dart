import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/amplify_outputs.dart' as generated;
import 'package:note_ai_app/main.dart' as composition;

void main() {
  test('composition uses selected public outputs, with generated fallback', () {
    const selected = String.fromEnvironment('NOTEFLOW_AMPLIFY_OUTPUTS');
    expect(
      composition.amplifyConfig,
      selected.isEmpty ? generated.amplifyConfig : selected,
    );
    expect(jsonDecode(composition.amplifyConfig), isA<Map<String, dynamic>>());
  });
}
