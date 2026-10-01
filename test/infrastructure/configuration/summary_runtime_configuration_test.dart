import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/infrastructure/configuration/summary_runtime_configuration.dart';

/// A generated outputs document carrying both custom keys, as `backend.ts`
/// publishes them.
const String _outputsWithGeneratedEndpoint =
    '{'
    '"version": "1.5",'
    '"custom": {'
    '"syncApiEndpoint": "https://sync.example.com",'
    '"aiApiEndpoint": "https://generated.example.com"'
    '}'
    '}';

/// A generated outputs document that predates the Summary output key.
const String _outputsWithoutAiEndpoint =
    '{'
    '"custom": {"syncApiEndpoint": "https://sync.example.com"}'
    '}';

void main() {
  group('SummaryRuntimeConfiguration local mode', () {
    test('defaults to local without any endpoint', () {
      final SummaryRuntimeConfiguration configuration =
          SummaryRuntimeConfiguration();

      expect(configuration.mode, SummaryRuntimeMode.local);
      expect(configuration.endpoint, isNull);
      expect(configuration.failureCode, isNull);
      expect(configuration.canSummarize, isTrue);
      expect(configuration.isLocal, isTrue);
      expect(configuration.isRemote, isFalse);
    });

    test('treats a blank mode token as the unconfigured local default', () {
      final SummaryRuntimeConfiguration configuration =
          SummaryRuntimeConfiguration(mode: '  ');

      expect(configuration.mode, SummaryRuntimeMode.local);
      expect(configuration.canSummarize, isTrue);
    });

    test('accepts an explicitly trimmed local mode token', () {
      final SummaryRuntimeConfiguration configuration =
          SummaryRuntimeConfiguration(mode: ' local ');

      expect(configuration.mode, SummaryRuntimeMode.local);
      expect(configuration.endpoint, isNull);
    });

    test('ignores a valid remote endpoint configuration', () {
      final SummaryRuntimeConfiguration configuration =
          SummaryRuntimeConfiguration(
            mode: 'local',
            explicitEndpoint: 'https://explicit.example.com',
            amplifyOutputsJson: _outputsWithGeneratedEndpoint,
          );

      expect(configuration.mode, SummaryRuntimeMode.local);
      expect(configuration.endpoint, isNull);
      expect(configuration.failureCode, isNull);
      expect(configuration.canSummarize, isTrue);
    });

    test('stays valid when the remote endpoint is malformed', () {
      final SummaryRuntimeConfiguration configuration =
          SummaryRuntimeConfiguration(
            mode: 'local',
            explicitEndpoint: 'not a uri',
            amplifyOutputsJson: '{not json',
          );

      expect(configuration.mode, SummaryRuntimeMode.local);
      expect(configuration.endpoint, isNull);
      expect(configuration.failureCode, isNull);
      expect(configuration.canSummarize, isTrue);
    });
  });

  group('SummaryRuntimeConfiguration remote mode', () {
    test('prefers the explicit endpoint over the generated output', () {
      final SummaryRuntimeConfiguration configuration =
          SummaryRuntimeConfiguration(
            mode: 'remote',
            explicitEndpoint: 'https://explicit.example.com',
            amplifyOutputsJson: _outputsWithGeneratedEndpoint,
          );

      expect(configuration.mode, SummaryRuntimeMode.remote);
      expect(configuration.endpoint, Uri.parse('https://explicit.example.com'));
      expect(configuration.failureCode, isNull);
      expect(configuration.canSummarize, isTrue);
      expect(configuration.isRemote, isTrue);
      expect(configuration.isLocal, isFalse);
    });

    test('falls back to custom.aiApiEndpoint in the generated outputs', () {
      final SummaryRuntimeConfiguration configuration =
          SummaryRuntimeConfiguration(
            mode: 'remote',
            amplifyOutputsJson: _outputsWithGeneratedEndpoint,
          );

      expect(configuration.mode, SummaryRuntimeMode.remote);
      expect(
        configuration.endpoint,
        Uri.parse('https://generated.example.com'),
      );
      expect(configuration.failureCode, isNull);
      expect(configuration.canSummarize, isTrue);
    });

    test('treats a blank explicit endpoint as absent before fallback', () {
      final SummaryRuntimeConfiguration configuration =
          SummaryRuntimeConfiguration(
            mode: 'remote',
            explicitEndpoint: ' \t\n ',
            amplifyOutputsJson: _outputsWithGeneratedEndpoint,
          );

      expect(
        configuration.endpoint,
        Uri.parse('https://generated.example.com'),
      );
    });

    test('accepts a base URI with an explicit port and path', () {
      final SummaryRuntimeConfiguration configuration =
          SummaryRuntimeConfiguration(
            mode: 'remote',
            explicitEndpoint: 'https://api.example.com:8443/ai',
          );

      expect(
        configuration.endpoint,
        Uri.parse('https://api.example.com:8443/ai'),
      );
      expect(configuration.canSummarize, isTrue);
    });

    test('never adopts a provider credential key as the endpoint', () {
      final SummaryRuntimeConfiguration configuration =
          SummaryRuntimeConfiguration(
            mode: 'remote',
            amplifyOutputsJson:
                '{"custom":{"aiApiKey":"sk-should-not-be-used"}}',
          );

      expect(configuration.mode, SummaryRuntimeMode.unavailable);
      expect(
        configuration.failureCode,
        SummaryRuntimeFailureCode.missingEndpoint,
      );
      expect(configuration.endpoint, isNull);
      expect(configuration.canSummarize, isFalse);
      expect(
        configuration.toString(),
        isNot(contains('sk-should-not-be-used')),
      );
    });
  });

  group('SummaryRuntimeConfiguration fail-closed selection', () {
    test('refuses an unknown mode without falling back to local', () {
      final SummaryRuntimeConfiguration configuration =
          SummaryRuntimeConfiguration(
            mode: 'cloud',
            explicitEndpoint: 'https://explicit.example.com',
            amplifyOutputsJson: _outputsWithGeneratedEndpoint,
          );

      expect(configuration.mode, SummaryRuntimeMode.unavailable);
      expect(configuration.mode, isNot(SummaryRuntimeMode.local));
      expect(configuration.failureCode, SummaryRuntimeFailureCode.unknownMode);
      expect(configuration.endpoint, isNull);
      expect(configuration.canSummarize, isFalse);
      expect(configuration.isLocal, isFalse);
      expect(configuration.isRemote, isFalse);
    });

    test('refuses remote mode without any endpoint value', () {
      final SummaryRuntimeConfiguration configuration =
          SummaryRuntimeConfiguration(mode: 'remote');

      expect(configuration.mode, SummaryRuntimeMode.unavailable);
      expect(
        configuration.failureCode,
        SummaryRuntimeFailureCode.missingEndpoint,
      );
      expect(configuration.endpoint, isNull);
      expect(configuration.canSummarize, isFalse);
    });

    test('refuses remote mode when the generated output key is absent', () {
      final SummaryRuntimeConfiguration configuration =
          SummaryRuntimeConfiguration(
            mode: 'remote',
            amplifyOutputsJson: _outputsWithoutAiEndpoint,
          );

      expect(
        configuration.failureCode,
        SummaryRuntimeFailureCode.missingEndpoint,
      );
      expect(configuration.canSummarize, isFalse);
    });

    test('refuses remote mode when the generated outputs are unreadable', () {
      final SummaryRuntimeConfiguration configuration =
          SummaryRuntimeConfiguration(
            mode: 'remote',
            amplifyOutputsJson: '{not json',
          );

      expect(configuration.mode, SummaryRuntimeMode.unavailable);
      expect(
        configuration.failureCode,
        SummaryRuntimeFailureCode.missingEndpoint,
      );
      expect(configuration.canSummarize, isFalse);
    });

    test('refuses an endpoint that is not an absolute https URI', () {
      const List<String> rejected = <String>[
        'api.example.com',
        'not a uri',
        'http://api.example.com',
        'https://',
        'ftp://api.example.com',
        'https:/api.example.com',
      ];

      for (int index = 0; index < rejected.length; index++) {
        final SummaryRuntimeConfiguration configuration =
            SummaryRuntimeConfiguration(
              mode: 'remote',
              explicitEndpoint: rejected[index],
            );

        expect(
          configuration.mode,
          SummaryRuntimeMode.unavailable,
          reason: 'case $index',
        );
        expect(
          configuration.failureCode,
          SummaryRuntimeFailureCode.invalidEndpoint,
          reason: 'case $index',
        );
        expect(configuration.endpoint, isNull, reason: 'case $index');
        expect(configuration.canSummarize, isFalse, reason: 'case $index');
      }
    });

    test('refuses an endpoint with userinfo, query, or fragment', () {
      const List<String> rejected = <String>[
        'https://user:pass@api.example.com',
        'https://user@api.example.com',
        'https://api.example.com?stage=section',
        'https://api.example.com#fragment',
      ];

      for (int index = 0; index < rejected.length; index++) {
        final SummaryRuntimeConfiguration configuration =
            SummaryRuntimeConfiguration(
              mode: 'remote',
              explicitEndpoint: rejected[index],
            );

        expect(
          configuration.failureCode,
          SummaryRuntimeFailureCode.invalidEndpoint,
          reason: 'case $index',
        );
        expect(configuration.canSummarize, isFalse, reason: 'case $index');
      }
    });

    test('refuses a generated endpoint with the same constraints', () {
      final SummaryRuntimeConfiguration configuration =
          SummaryRuntimeConfiguration(
            mode: 'remote',
            amplifyOutputsJson:
                '{"custom":{"aiApiEndpoint":"http://insecure.example.com"}}',
          );

      expect(
        configuration.failureCode,
        SummaryRuntimeFailureCode.invalidEndpoint,
      );
      expect(configuration.endpoint, isNull);
      expect(configuration.canSummarize, isFalse);
    });

    test('keeps canSummarize consistent with the failure code', () {
      final List<SummaryRuntimeConfiguration> configurations =
          <SummaryRuntimeConfiguration>[
            SummaryRuntimeConfiguration(),
            SummaryRuntimeConfiguration(
              mode: 'remote',
              explicitEndpoint: 'https://api.example.com',
            ),
            SummaryRuntimeConfiguration(mode: 'remote'),
            SummaryRuntimeConfiguration(mode: 'other'),
          ];

      for (final SummaryRuntimeConfiguration configuration in configurations) {
        expect(
          configuration.canSummarize,
          configuration.failureCode == null,
          reason: configuration.mode.name,
        );
      }
    });
  });

  group('SummaryRuntimeConfiguration diagnostics', () {
    test('never prints the remote endpoint', () {
      final SummaryRuntimeConfiguration configuration =
          SummaryRuntimeConfiguration(
            mode: 'remote',
            explicitEndpoint: 'https://explicit.example.com',
          );

      expect(configuration.toString(), contains('remote'));
      expect(configuration.toString(), isNot(contains('explicit.example.com')));
      expect(configuration.toString(), isNot(contains('https://')));
    });

    test('never prints a rejected endpoint value', () {
      final SummaryRuntimeConfiguration configuration =
          SummaryRuntimeConfiguration(
            mode: 'remote',
            explicitEndpoint: 'https://user:pass@api.example.com',
          );

      expect(configuration.toString(), contains('invalidEndpoint'));
      expect(configuration.toString(), isNot(contains('api.example.com')));
      expect(configuration.toString(), isNot(contains('user:pass')));
    });

    test('reports only a safe code for an invalid remote build', () {
      final SummaryRuntimeConfiguration configuration =
          SummaryRuntimeConfiguration(
            mode: 'remote',
            explicitEndpoint: 'http://api.example.com',
          );

      expect(
        configuration.toString(),
        'SummaryRuntimeConfiguration('
        'mode: unavailable, canSummarize: false, '
        'failureCode: invalidEndpoint)',
      );
      expect(configuration.failureCode?.name, 'invalidEndpoint');
    });
  });

  group('SummaryRuntimeConfiguration compile-time wiring', () {
    test('names the defines and the generated output key', () {
      expect(
        SummaryRuntimeConfiguration.modeEnvironmentKey,
        'NOTEFLOW_AI_MODE',
      );
      expect(
        SummaryRuntimeConfiguration.endpointEnvironmentKey,
        'NOTEFLOW_AI_API',
      );
      expect(SummaryRuntimeConfiguration.generatedEndpointKey, 'aiApiEndpoint');
      expect(SummaryRuntimeConfiguration.localModeToken, 'local');
      expect(SummaryRuntimeConfiguration.remoteModeToken, 'remote');
    });

    test('fromEnvironment reads exactly the two compile-time defines', () {
      const String rawMode = String.fromEnvironment(
        SummaryRuntimeConfiguration.modeEnvironmentKey,
      );
      const String rawEndpoint = String.fromEnvironment(
        SummaryRuntimeConfiguration.endpointEnvironmentKey,
      );

      final SummaryRuntimeConfiguration fromEnvironment =
          SummaryRuntimeConfiguration.fromEnvironment(
            amplifyOutputsJson: _outputsWithGeneratedEndpoint,
          );
      final SummaryRuntimeConfiguration expected = SummaryRuntimeConfiguration(
        mode: rawMode,
        explicitEndpoint: rawEndpoint,
        amplifyOutputsJson: _outputsWithGeneratedEndpoint,
      );

      expect(fromEnvironment.mode, expected.mode);
      expect(fromEnvironment.endpoint, expected.endpoint);
      expect(fromEnvironment.failureCode, expected.failureCode);
      expect(fromEnvironment.canSummarize, expected.canSummarize);
    });
  });
}
