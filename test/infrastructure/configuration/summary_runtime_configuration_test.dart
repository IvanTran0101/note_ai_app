import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/infrastructure/configuration/summary_runtime_configuration.dart';

const _generatedOutputs = '''
{"custom":{"aiApiEndpoint":"https://generated.example.test/v1"}}
''';

void main() {
  test('blank mode uses the generated cloud endpoint', () {
    final config = SummaryRuntimeConfiguration(
      mode: ' ',
      amplifyOutputsJson: _generatedOutputs,
    );

    expect(config.mode, SummaryRuntimeMode.remote);
    expect(config.endpoint, Uri.parse('https://generated.example.test/v1'));
  });

  test('explicit remote mode and endpoint take precedence', () {
    final config = SummaryRuntimeConfiguration(
      mode: ' remote ',
      explicitEndpoint: ' https://override.example.test/v1 ',
      amplifyOutputsJson: _generatedOutputs,
    );

    expect(config.canSummarize, isTrue);
    expect(config.endpoint, Uri.parse('https://override.example.test/v1'));
  });

  test('obsolete local mode and unknown modes disable Summary', () {
    for (final mode in ['local', 'unknown']) {
      final config = SummaryRuntimeConfiguration(
        mode: mode,
        amplifyOutputsJson: _generatedOutputs,
      );

      expect(config.canSummarize, isFalse, reason: mode);
      expect(config.endpoint, isNull, reason: mode);
      expect(config.failureCode, SummaryRuntimeFailureCode.unknownMode);
    }
  });

  test('missing and invalid endpoints leave Summary unavailable', () {
    final missing = SummaryRuntimeConfiguration(amplifyOutputsJson: '{}');
    expect(missing.canSummarize, isFalse);
    expect(missing.failureCode, SummaryRuntimeFailureCode.missingEndpoint);

    for (final endpoint in [
      'http://override.example.test',
      'https://user@override.example.test',
      'https://override.example.test?query',
      'https://override.example.test#fragment',
    ]) {
      final config = SummaryRuntimeConfiguration(
        explicitEndpoint: endpoint,
        amplifyOutputsJson: _generatedOutputs,
      );

      expect(config.canSummarize, isFalse);
      expect(config.endpoint, isNull);
      expect(config.failureCode, SummaryRuntimeFailureCode.invalidEndpoint);
      expect(config.toString(), isNot(contains('override.example.test')));
    }
  });
}
